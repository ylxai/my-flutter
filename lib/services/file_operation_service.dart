import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../constants/file_constants.dart';
import '../models/file_item.dart';
import '../models/copy_result.dart';
import '../models/performance_settings.dart';

/// Thread-safe work queue untuk parallel copy.
///
/// Dart berjalan di single-threaded event loop, namun akses [ListQueue]
/// dari multiple `async` workers tetap bisa menghasilkan race condition
/// karena setiap `await` memberi kesempatan worker lain berjalan.
///
/// Solusi: gunakan integer index atomik yang di-increment sekali per
/// item — operasi `_nextIndex++` bersifat atomic di Dart event loop
/// sehingga tidak ada dua worker yang mendapat index yang sama.
class _AtomicWorkQueue {
  final List<FileItem> _items;
  int _nextIndex = 0;

  _AtomicWorkQueue(List<FileItem> items) : _items = List.unmodifiable(items);

  /// Ambil item berikutnya. Mengembalikan `null` jika queue sudah habis.
  /// Operasi ini atomic di Dart event loop — tidak ada await di antara
  /// pembacaan dan increment [_nextIndex].
  FileItem? dequeue() {
    if (_nextIndex >= _items.length) return null;
    return _items[_nextIndex++];
  }

  bool get isEmpty => _nextIndex >= _items.length;
}

/// Shared mutable counter yang aman diakses dari multiple async workers
/// di Dart single-threaded event loop. Setiap increment adalah atomic
/// karena tidak ada `await` di dalam operasi increment.
class _SafeCounter {
  int _value = 0;
  int get value => _value;
  void increment([int by = 1]) => _value += by;
}

/// Service for file operations - validation, copy, and scanning.
/// Supports pause, resume, and cancel during copy.
class FileOperationService {
  final PerformanceSettings settings;

  FileOperationService({PerformanceSettings? settings})
    : settings = settings ?? PerformanceSettings.autoConfigure();

  // ── Pause / Cancel state ──

  bool _isPaused = false;
  bool _isCancelled = false;
  Completer<void>? _pauseCompleter;

  /// Pause the running copy operation.
  void pauseCopy() {
    if (!_isPaused) {
      _isPaused = true;
      _pauseCompleter = Completer<void>();
    }
  }

  /// Resume a paused copy operation.
  void resumeCopy() {
    if (_isPaused) {
      _isPaused = false;
      _pauseCompleter?.complete();
      _pauseCompleter = null;
    }
  }

  /// Cancel the running copy operation.
  void cancelCopy() {
    _isCancelled = true;
    // If paused, also resume so the loop can exit
    if (_isPaused) {
      resumeCopy();
    }
  }

  /// Reset flags before starting a new operation.
  void _resetFlags() {
    _isPaused = false;
    _isCancelled = false;
    _pauseCompleter = null;
  }

  bool get isPaused => _isPaused;
  bool get isCancelled => _isCancelled;

  // ── Validation ──

  /// Validate files exist in source folder and match by name.
  ///
  /// Menggunakan [kCopyExtensions] dari [file_constants.dart] sebagai default
  /// sehingga tidak ada duplikasi daftar ekstensi di berbagai tempat.
  ///
  /// Scan dibatasi oleh [ScanLimits.maxDepth] dan [ScanLimits.maxFiles]
  /// untuk mencegah hang jika user memilih folder sistem / drive root.
  Future<ValidationResult> validateFiles({
    required String sourceFolder,
    required List<String> fileNames,
    List<String> extensions = kCopyExtensions,
  }) async {
    return Isolate.run(() {
      final dir = Directory(sourceFolder);
      if (!dir.existsSync()) {
        return const ValidationResult(
          invalidFiles: [
            InvalidFileItem(path: '', reason: 'Source folder does not exist'),
          ],
        );
      }

      final normalizedExt = extensions.map((e) => e.toLowerCase()).toSet();
      final requestedNames = <String>{};
      for (final name in fileNames) {
        final trimmed = name.trim();
        if (trimmed.isNotEmpty) {
          requestedNames.add(trimmed.toLowerCase());
        }
      }

      // ✅ FIX P0-4: Scan dengan batas depth dan jumlah file maksimum.
      // Mencegah hang / OOM jika folder sangat dalam atau sangat besar.
      final allFiles = <String, List<File>>{};
      var scannedCount = 0;

      void scanDir(Directory current, int depth) {
        if (depth > ScanLimits.maxDepth) return;
        if (scannedCount >= ScanLimits.maxFiles) return;

        final List<FileSystemEntity> entities;
        try {
          entities = current.listSync(recursive: false, followLinks: false);
        } catch (_) {
          return; // Skip direktori yang tidak bisa diakses (permission denied)
        }

        for (final entity in entities) {
          if (scannedCount >= ScanLimits.maxFiles) return;

          if (entity is Directory) {
            scanDir(entity, depth + 1);
          } else if (entity is File) {
            final name = _fileNameWithoutExt(entity.path).toLowerCase();
            if (!requestedNames.contains(name)) continue;

            final ext = _fileExtension(entity.path).toLowerCase();
            if (!normalizedExt.contains(ext)) continue;

            allFiles.putIfAbsent(name, () => []).add(entity);
            scannedCount++;
          }
        }
      }

      scanDir(dir, 0);

      final validFiles = <FileItem>[];
      final invalidFiles = <InvalidFileItem>[];
      final seenNames = <String>{};
      var duplicates = 0;

      for (final name in fileNames) {
        final trimmed = name.trim();
        if (trimmed.isEmpty) continue;

        // Check duplicate
        if (seenNames.contains(trimmed.toLowerCase())) {
          duplicates++;
          continue;
        }
        seenNames.add(trimmed.toLowerCase());

        // Search for matching files
        final key = trimmed.toLowerCase();
        final matches = allFiles[key] ?? const [];
        bool found = false;
        for (final file in matches) {
          final stat = file.statSync();
          validFiles.add(
            FileItem(
              path: file.path,
              name: _fileName(file.path),
              size: stat.size,
              createdDate: stat.changed,
              modifiedDate: stat.modified,
            ),
          );
          found = true;
        }

        if (!found) {
          invalidFiles.add(
            InvalidFileItem(
              path: trimmed,
              reason: 'File not found in source folder',
            ),
          );
        }
      }

      // Remove duplicates from valid files
      final uniqueValid = <String, FileItem>{};
      for (final f in validFiles) {
        uniqueValid[f.path] = f;
      }

      return ValidationResult(
        validFiles: uniqueValid.values.toList(),
        invalidFiles: invalidFiles,
        duplicatesRemoved: duplicates,
      );
    });
  }

  // ── Copy Operations (with Pause/Cancel) ──

  /// Copy files with progress reporting, pause, and cancel support.
  Stream<CopyProgress> copyFiles({
    required List<FileItem> files,
    required String destinationFolder,
    bool skipExisting = true,
  }) async* {
    _resetFlags();

    if (files.isEmpty) {
      return;
    }

    final startTime = DateTime.now();
    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);
    var processedFiles = 0;
    var bytesCopied = 0;
    var skippedCount = 0;
    var failedCount = 0;

    final parallelism = settings.maxParallelism.clamp(1, files.length);
    if (parallelism > 1) {
      final controller = StreamController<CopyProgress>(
        onCancel: () {
          _isCancelled = true;
          if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
            _pauseCompleter!.complete();
          }
        },
      );

      // ✅ FIX P0-1: Gunakan _AtomicWorkQueue (index-based) dan _SafeCounter
      // sebagai pengganti ListQueue + shared int variables.
      // Operasi dequeue() dan counter.increment() tidak mengandung await
      // sehingga bersifat atomic di Dart single-threaded event loop —
      // tidak ada dua worker yang bisa mengambil item yang sama.
      final workQueue = _AtomicWorkQueue(files);
      final processedCounter = _SafeCounter();
      final bytesCounter = _SafeCounter();
      final skippedCounter = _SafeCounter();
      final failedCounter = _SafeCounter();

      Future<void> worker() async {
        while (true) {
          if (_isCancelled) return;

          // dequeue() adalah atomic: baca + increment index tanpa await
          final file = workQueue.dequeue();
          if (file == null) return; // queue habis, worker selesai

          if (_isPaused) {
            controller.add(
              _makeProgress(
                files.length,
                processedCounter.value,
                '⏸ Paused',
                bytesCounter.value,
                totalBytes,
                startTime,
                skippedCounter.value,
                failedCounter.value,
              ),
            );
            await _pauseCompleter?.future;
            if (_isCancelled) return;
          }

          final subFolder = file.isRaw ? 'RAW' : 'JPG';
          final destDir = Directory(
            '$destinationFolder${Platform.pathSeparator}$subFolder',
          );

          if (!destDir.existsSync()) {
            destDir.createSync(recursive: true);
          }

          final destPath =
              '${destDir.path}${Platform.pathSeparator}${file.name}';

          try {
            if (skipExisting && _shouldSkipExisting(file, destPath)) {
              // increment() atomic: tidak ada await di dalamnya
              skippedCounter.increment();
              processedCounter.increment();
              controller.add(
                _makeProgress(
                  files.length,
                  processedCounter.value,
                  file.name,
                  bytesCounter.value,
                  totalBytes,
                  startTime,
                  skippedCounter.value,
                  failedCounter.value,
                ),
              );
              continue;
            }

            await File(file.path).copy(destPath);
            // increment setelah await selesai — masih atomic karena
            // tidak ada await lain di antara operasi increment
            bytesCounter.increment(file.size);
          } catch (e) {
            failedCounter.increment();
          }

          processedCounter.increment();

          controller.add(
            _makeProgress(
              files.length,
              processedCounter.value,
              file.name,
              bytesCounter.value,
              totalBytes,
              startTime,
              skippedCounter.value,
              failedCounter.value,
            ),
          );
        }
      }

      final workers = List.generate(parallelism, (_) => worker());
      Future.wait(workers).then((_) {
        if (_isCancelled) {
          controller.add(
            _makeProgress(
              files.length,
              processedCounter.value,
              'Cancelled',
              bytesCounter.value,
              totalBytes,
              startTime,
              skippedCounter.value,
              failedCounter.value,
            ),
          );
        }
        controller.close();
      });

      yield* controller.stream;
      return;
    }

    for (final file in files) {
      // ── Check cancel ──
      if (_isCancelled) {
        yield _makeProgress(
          files.length,
          processedFiles,
          'Cancelled',
          bytesCopied,
          totalBytes,
          startTime,
          skippedCount,
          failedCount,
        );
        return;
      }

      // ── Check pause ──
      if (_isPaused) {
        yield _makeProgress(
          files.length,
          processedFiles,
          '⏸ Paused',
          bytesCopied,
          totalBytes,
          startTime,
          skippedCount,
          failedCount,
        );
        await _pauseCompleter?.future;
        // After resume, check cancel again
        if (_isCancelled) {
          yield _makeProgress(
            files.length,
            processedFiles,
            'Cancelled',
            bytesCopied,
            totalBytes,
            startTime,
            skippedCount,
            failedCount,
          );
          return;
        }
      }

      final subFolder = file.isRaw ? 'RAW' : 'JPG';
      final destDir = Directory(
        '$destinationFolder${Platform.pathSeparator}$subFolder',
      );

      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }

      final destPath = '${destDir.path}${Platform.pathSeparator}${file.name}';

      try {
        if (skipExisting && _shouldSkipExisting(file, destPath)) {
          skippedCount++;
          processedFiles++;
          continue;
        }

        await File(file.path).copy(destPath);
        bytesCopied += file.size;
      } catch (e) {
        failedCount++;
      }

      processedFiles++;

      yield _makeProgress(
        files.length,
        processedFiles,
        file.name,
        bytesCopied,
        totalBytes,
        startTime,
        skippedCount,
        failedCount,
      );
    }
  }

  CopyProgress _makeProgress(
    int totalFiles,
    int processedFiles,
    String currentFileName,
    int bytesCopied,
    int totalBytes,
    DateTime startTime,
    int skippedCount,
    int failedCount,
  ) {
    final elapsed = DateTime.now().difference(startTime);
    final speedMBps = elapsed.inMilliseconds > 0
        ? (bytesCopied / 1024 / 1024) / (elapsed.inMilliseconds / 1000)
        : 0.0;

    return CopyProgress(
      totalFiles: totalFiles,
      processedFiles: processedFiles,
      currentFileName: currentFileName,
      bytesCopied: bytesCopied,
      totalBytes: totalBytes,
      speedMBps: speedMBps,
      skippedCount: skippedCount,
      failedCount: failedCount,
      elapsed: elapsed,
    );
  }

  // ── Folder Scanning ──

  /// Scan a folder for all image files.
  ///
  /// Menggunakan [kScanExtensions] dari [file_constants.dart] sebagai default.
  ///
  /// ✅ FIX P0-3 + P0-4: Pakai konstanta terpusat + batas scan aman.
  /// Scan dibatasi [ScanLimits.maxDepth] level kedalaman dan
  /// [ScanLimits.maxFiles] jumlah file untuk mencegah hang pada folder besar.
  /// Symlink tidak di-follow untuk mencegah infinite loop.
  Future<List<FileItem>> scanFolder(
    String folderPath, {
    List<String> extensions = kScanExtensions,
  }) async {
    return Isolate.run(() {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) return <FileItem>[];

      final normalizedExt = extensions.map((e) => e.toLowerCase()).toSet();
      final results = <FileItem>[];

      // Rekursif manual dengan batas depth dan jumlah file.
      // Tidak menggunakan listSync(recursive: true) karena tidak bisa
      // dibatasi depth-nya dan bisa hang pada folder sistem.
      void scanDir(Directory current, int depth) {
        if (depth > ScanLimits.maxDepth) return;
        if (results.length >= ScanLimits.maxFiles) return;

        final List<FileSystemEntity> entities;
        try {
          entities = current.listSync(recursive: false, followLinks: false);
        } catch (_) {
          return; // Skip folder yang tidak bisa diakses (permission denied)
        }

        for (final entity in entities) {
          if (results.length >= ScanLimits.maxFiles) return;

          if (entity is Directory) {
            scanDir(entity, depth + 1);
          } else if (entity is File) {
            final ext = _fileExtension(entity.path).toLowerCase();
            if (!normalizedExt.contains(ext)) continue;

            try {
              final stat = entity.statSync();
              results.add(
                FileItem(
                  path: entity.path,
                  name: _fileName(entity.path),
                  size: stat.size,
                  createdDate: stat.changed,
                  modifiedDate: stat.modified,
                ),
              );
            } catch (_) {
              // Skip file yang tidak bisa dibaca stat-nya
            }
          }
        }
      }

      scanDir(dir, 0);
      return results;
    });
  }

  // ── Helper functions ──

  static String _fileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  static String _fileNameWithoutExt(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(0, dot) : name;
  }

  static String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot + 1) : '';
  }

  bool _shouldSkipExisting(FileItem file, String destPath) {
    final destFile = File(destPath);
    if (!destFile.existsSync()) return false;

    final destStat = destFile.statSync();
    if (destStat.size != file.size) return false;

    final sourceModified =
        file.modifiedDate ?? File(file.path).statSync().modified;
    return !destStat.modified.isBefore(sourceModified);
  }
}
