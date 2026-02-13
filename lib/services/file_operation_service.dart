import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../models/file_item.dart';
import '../models/copy_result.dart';
import '../models/performance_settings.dart';

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

  /// Validate files exist in source folder and match by name
  Future<ValidationResult> validateFiles({
    required String sourceFolder,
    required List<String> fileNames,
    List<String> extensions = const [
      'cr2', 'cr3', 'nef', 'arw', 'raf', 'orf',
      'rw2', 'dng', 'raw', 'pef', 'srw',
      'jpg', 'jpeg',
    ],
  }) async {
    return Isolate.run(() {
      final dir = Directory(sourceFolder);
      if (!dir.existsSync()) {
        return const ValidationResult(
          invalidFiles: [
            InvalidFileItem(
              path: '',
              reason: 'Source folder does not exist',
            ),
          ],
        );
      }

      // Scan all files in source folder
      final allFiles = <String, FileSystemEntity>{};
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          final name = _fileNameWithoutExt(entity.path);
          allFiles[name.toLowerCase()] = entity;
        }
      }

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
        bool found = false;
        final key = trimmed.toLowerCase();
        for (final entry in allFiles.entries) {
          if (entry.key == key) {
            final file = File(entry.value.path);
            final ext2 = _fileExtension(file.path);
            if (extensions.any(
              (e) => e.toLowerCase() == ext2.toLowerCase(),
            )) {
              final stat = file.statSync();
              validFiles.add(FileItem(
                path: file.path,
                name: _fileName(file.path),
                size: stat.size,
                createdDate: stat.changed,
                modifiedDate: stat.modified,
              ));
              found = true;
            }
          }
        }

        if (!found) {
          invalidFiles.add(InvalidFileItem(
            path: trimmed,
            reason: 'File not found in source folder',
          ));
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

    final startTime = DateTime.now();
    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);
    var processedFiles = 0;
    var bytesCopied = 0;
    var skippedCount = 0;
    var failedCount = 0;

    for (final file in files) {
      // ── Check cancel ──
      if (_isCancelled) {
        yield _makeProgress(
          files.length, processedFiles, 'Cancelled',
          bytesCopied, totalBytes, startTime,
          skippedCount, failedCount,
        );
        return;
      }

      // ── Check pause ──
      if (_isPaused) {
        yield _makeProgress(
          files.length, processedFiles, '⏸ Paused',
          bytesCopied, totalBytes, startTime,
          skippedCount, failedCount,
        );
        await _pauseCompleter?.future;
        // After resume, check cancel again
        if (_isCancelled) {
          yield _makeProgress(
            files.length, processedFiles, 'Cancelled',
            bytesCopied, totalBytes, startTime,
            skippedCount, failedCount,
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

      final destPath =
          '${destDir.path}${Platform.pathSeparator}${file.name}';

      try {
        // Smart copy: skip if same size
        if (skipExisting) {
          final destFile = File(destPath);
          if (destFile.existsSync() &&
              destFile.lengthSync() == file.size) {
            skippedCount++;
            processedFiles++;
            continue;
          }
        }

        // Copy file
        await File(file.path).copy(destPath);
        bytesCopied += file.size;
      } catch (e) {
        failedCount++;
      }

      processedFiles++;

      yield _makeProgress(
        files.length, processedFiles, file.name,
        bytesCopied, totalBytes, startTime,
        skippedCount, failedCount,
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
        ? (bytesCopied / 1024 / 1024) /
            (elapsed.inMilliseconds / 1000)
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

  /// Scan a folder for all image files
  Future<List<FileItem>> scanFolder(
    String folderPath, {
    List<String> extensions = const [
      'cr2', 'cr3', 'nef', 'arw', 'raf', 'orf',
      'rw2', 'dng', 'raw', 'pef', 'srw',
      'jpg', 'jpeg', 'png',
    ],
  }) async {
    return Isolate.run(() {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) return <FileItem>[];

      final results = <FileItem>[];

      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          final ext = _fileExtension(entity.path).toLowerCase();
          if (extensions.any((e) => e.toLowerCase() == ext)) {
            final stat = entity.statSync();
            results.add(FileItem(
              path: entity.path,
              name: _fileName(entity.path),
              size: stat.size,
              createdDate: stat.changed,
              modifiedDate: stat.modified,
            ));
          }
        }
      }

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
}
