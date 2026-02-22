// Upload orchestrator service.
//
// Coordinates the full upload pipeline:
// 1. Scan source folder for images
// 2. Process images via Rust (resize + WebP)
// 3. Upload thumbnails/previews to R2
// 4. Optionally upload originals to Google Drive
// 5. Generate and upload manifest.json to R2

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/file_constants.dart';
import '../models/cloud_account.dart';
import '../src/rust/api.dart' as rust;
import '../utils/file_utils.dart';
import 'r2_upload_service.dart';
import 'google_drive_upload_service.dart';

/// Progress phases for the upload pipeline
enum UploadPhase {
  scanning,
  processing,
  uploadingToR2,
  uploadingToDrive,
  generatingManifest,
  completed,
  error,
}

/// Progress update from the upload pipeline
class UploadProgress {
  final UploadPhase phase;
  final int currentFile;
  final int totalFiles;
  final String currentFileName;
  final String message;
  final double overallProgress;
  final String galleryUrl;
  final int successCount;
  final int failedCount;
  final Duration totalDuration;

  const UploadProgress({
    required this.phase,
    this.currentFile = 0,
    this.totalFiles = 0,
    this.currentFileName = '',
    this.message = '',
    this.overallProgress = 0.0,
    this.galleryUrl = '',
    this.successCount = 0,
    this.failedCount = 0,
    this.totalDuration = Duration.zero,
  });
}

/// Result of a completed upload
class UploadResult {
  final String eventName;
  final String galleryUrl;
  final String? driveFolderId;
  final int totalPhotos;
  final int successCount;
  final int failedCount;
  final Duration totalDuration;

  const UploadResult({
    required this.eventName,
    required this.galleryUrl,
    this.driveFolderId,
    required this.totalPhotos,
    required this.successCount,
    required this.failedCount,
    required this.totalDuration,
  });
}

/// Orchestrates the entire upload pipeline
class UploadOrchestrator {
  final R2UploadService _r2Service;
  final GoogleDriveUploadService _driveService;
  static const _retryOptions = _RetryOptions(
    maxRetries: 3,
    baseDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 10),
    backoffFactor: 2.0,
    jitterRatio: 0.2,
  );

  bool _isCancelled = false;

  UploadOrchestrator({
    required R2UploadService r2Service,
    required GoogleDriveUploadService driveService,
  }) : _r2Service = r2Service,
       _driveService = driveService;

  /// Cancel the current upload
  void cancel() {
    _isCancelled = true;
  }

  /// Execute the full upload pipeline
  Stream<UploadProgress> execute(UploadConfig config) async* {
    _isCancelled = false;
    final stopwatch = Stopwatch()..start();

    // Phase 1: Scan source folder
    yield const UploadProgress(
      phase: UploadPhase.scanning,
      message: 'Scanning source folder...',
    );

    // ✅ FIX kiloconnect WARNING: Gunakan config.extensions dari user settings
    // bukan hardcode ['.jpg', '.jpeg', '.png'].
    // config.extensions sudah dibangun di publish_page.dart dari settings
    // (rawExtensions + jpgExtensions + kExtraImageExtensions) sehingga
    // menghormati preferensi user. Scan sekarang akurat sesuai settings.
    final scannedFiles = await _scanForImages(
      config.sourceFolder,
      recursive: config.recursiveScan,
      extensions: config.extensions,
    );
    if (_isCancelled) return;

    final imageFiles = scannedFiles;

    yield UploadProgress(
      phase: UploadPhase.scanning,
      currentFile: imageFiles.length,
      totalFiles: imageFiles.length,
      message: 'Found ${imageFiles.length} processable image(s)',
      overallProgress: 0.05,
    );

    if (imageFiles.isEmpty) {
      yield const UploadProgress(
        phase: UploadPhase.error,
        message: 'No processable image files found in source folder.',
      );
      return;
    }

    final totalFiles = imageFiles.length;

    Directory? tempDir;
    try {
      // Phase 2: Process images via Rust backend
      yield UploadProgress(
        phase: UploadPhase.processing,
        totalFiles: totalFiles,
        message: 'Processing images (resize + WebP)...',
        overallProgress: 0.1,
      );

      tempDir = await _createTempOutputDir();

      final results = await rust.processImagesForUpload(
        sourcePaths: imageFiles.map((f) => f.path).toList(),
        outputDir: tempDir.path,
        thumbWidth: config.thumbWidth,
        previewWidth: config.previewWidth,
        thumbQuality: config.thumbQuality,
        previewQuality: config.previewQuality,
      );

      if (_isCancelled) return;

      // ✅ FIX #3: Continue-on-error di image processing.
      // Sebelumnya: 1 file gagal decode → abort seluruh batch.
      // Sekarang: pisahkan sukses vs gagal, lanjutkan dengan yang sukses.
      final processingFailed = results.where((r) => !r.success).toList();
      final processedFiles = results
          .where((r) => r.success)
          .map(
            (r) => _ProcessedFile(
              sourcePath: r.sourcePath,
              thumbPath: r.thumbPath,
              previewPath: r.previewPath,
              name: p.basenameWithoutExtension(r.sourcePath),
            ),
          )
          .toList();

      // Jika SEMUA file gagal di-process, baru hentikan pipeline
      if (processedFiles.isEmpty) {
        final failedName = p.basename(processingFailed.first.sourcePath);
        yield UploadProgress(
          phase: UploadPhase.error,
          message:
              'Processing failed for all files. First error: $failedName — '
              '${processingFailed.first.errorMessage}',
          failedCount: processingFailed.length,
        );
        return;
      }

      yield UploadProgress(
        phase: UploadPhase.processing,
        currentFile: totalFiles,
        totalFiles: totalFiles,
        message: 'Processing complete',
        overallProgress: 0.3,
      );

      // Phase 3: Upload to R2
      // ✅ FIX #4: Ganti serial for-loop dengan concurrent upload.
      // Serial upload (1 file at a time) sangat lambat untuk 100+ foto.
      // Gunakan Future.wait dengan concurrency limit (5 paralel) agar:
      // - Tidak overload R2 / network dengan unlimited concurrency
      // - Jauh lebih cepat dari serial (5x throughput)
      // - Masih continue-on-error seperti sebelumnya
      const int r2Concurrency = 5;
      final eventSlug = _slugify(config.eventName);
      int uploadedR2 = 0;
      int r2FailedCount = 0;
      final r2Errors = <String>[];
      final successfulFiles = <_ProcessedFile>[];

      // Proses file dalam batch concurrency
      for (var i = 0; i < processedFiles.length; i += r2Concurrency) {
        if (_isCancelled) return;

        final batch = processedFiles.sublist(
          i,
          (i + r2Concurrency).clamp(0, processedFiles.length),
        );

        // Upload thumb + preview untuk setiap file dalam batch secara paralel
        final batchResults = await Future.wait(
          batch.map((pf) async {
            try {
              // Upload thumb dan preview secara paralel per file
              await Future.wait([
                _withRetry(
                  action: () => _r2Service.uploadFile(
                    filePath: pf.thumbPath,
                    objectKey: '$eventSlug/thumbs/${pf.name}.webp',
                    contentType: 'image/webp',
                  ),
                  isRetryable: _isRetryableR2,
                ),
                _withRetry(
                  action: () => _r2Service.uploadFile(
                    filePath: pf.previewPath,
                    objectKey: '$eventSlug/previews/${pf.name}.webp',
                    contentType: 'image/webp',
                  ),
                  isRetryable: _isRetryableR2,
                ),
              ]);
              return (file: pf, success: true, error: '');
            } catch (e) {
              return (file: pf, success: false, error: e.toString());
            }
          }),
        );

        // Kumpulkan hasil batch
        for (final result in batchResults) {
          if (result.success) {
            uploadedR2 += 2; // thumb + preview
            successfulFiles.add(result.file);
          } else {
            r2FailedCount++;
            r2Errors.add('${result.file.name}: ${result.error}');
          }
        }

        // Emit progress setelah setiap batch selesai
        yield UploadProgress(
          phase: UploadPhase.uploadingToR2,
          currentFile: uploadedR2,
          totalFiles: processedFiles.length * 2,
          message:
              'Uploading to R2 ${successfulFiles.length}/${processedFiles.length}...',
          overallProgress:
              0.3 + (uploadedR2 / (processedFiles.length * 2)) * 0.4,
          failedCount: r2FailedCount,
        );
      }

      // Jika semua file R2 gagal, baru hentikan pipeline
      if (successfulFiles.isEmpty && totalFiles > 0) {
        yield UploadProgress(
          phase: UploadPhase.error,
          message:
              'R2 upload failed for all files. Errors: ${r2Errors.take(3).join('; ')}',
          failedCount: r2FailedCount,
        );
        return;
      }

      // Phase 4: Upload originals to Google Drive (if enabled)
      String? driveFolderId;
      // ✅ FIX reviewer: Hoist driveFailedCount ke outer scope agar bisa
      // dimasukkan ke failedCount final di completed event.
      int driveFailedCount = 0;
      if (config.uploadOriginalToDrive && _driveService.isAuthenticated) {
        try {
          driveFolderId = await _withRetry(
            action: () => _driveService.createFolder(config.eventName),
            isRetryable: _isRetryableDrive,
          );
          final folderId = driveFolderId;
          if (folderId == null) {
            throw Exception('Drive folder id missing');
          }
          await _withRetry(
            action: () => _driveService.makeFolderPublic(folderId),
            isRetryable: _isRetryableDrive,
          );
        } catch (e) {
          yield UploadProgress(
            phase: UploadPhase.error,
            message: 'Drive folder creation failed: $e',
          );
          return;
        }

        // Drive upload original — gunakan imageFiles (sudah difilter ke processable)
        final driveFiles = imageFiles;
        final folderId = driveFolderId;
        if (folderId == null) {
          yield const UploadProgress(
            phase: UploadPhase.error,
            message: 'Drive folder id missing after creation',
          );
          return;
        }
        // ✅ FIX #2: Ganti serial Drive upload dengan concurrent batch.
        // Serial upload sangat lambat untuk 100+ foto originl.
        // Gunakan pola yang sama dengan R2: Future.wait batch 3 paralel.
        // Drive API rate limit lebih ketat dari R2, jadi gunakan batch 3 (bukan 5).
        const int driveConcurrency = 3;
        int uploadedDrive = 0;

        for (var i = 0; i < driveFiles.length; i += driveConcurrency) {
          if (_isCancelled) return;

          final batch = driveFiles.sublist(
            i,
            (i + driveConcurrency).clamp(0, driveFiles.length),
          );

          final batchResults = await Future.wait(
            batch.map((file) async {
              try {
                await _withRetry(
                  action: () => _driveService.uploadFile(
                    filePath: file.path,
                    folderId: folderId,
                  ),
                  isRetryable: _isRetryableDrive,
                );
                return (name: p.basename(file.path), success: true);
              } catch (e) {
                return (name: p.basename(file.path), success: false);
              }
            }),
          );

          for (final result in batchResults) {
            if (result.success) {
              uploadedDrive++;
            } else {
              driveFailedCount++;
            }
          }

          yield UploadProgress(
            phase: UploadPhase.uploadingToDrive,
            currentFile: uploadedDrive,
            totalFiles: driveFiles.length,
            message:
                'Uploading to Drive $uploadedDrive/${driveFiles.length}...',
            overallProgress: 0.7 + (uploadedDrive / driveFiles.length) * 0.25,
            failedCount: driveFailedCount,
          );
        }
      }

      // Phase 5: Generate and upload manifest
      // ✅ FIX P1-1: Manifest hanya berisi file yang berhasil di-upload ke R2,
      // bukan semua processedFiles (beberapa mungkin gagal upload).
      // ✅ FIX reviewer: totalFailedCount menggabungkan R2 + Drive failures.
      final totalFailedCount = r2FailedCount + driveFailedCount;

      yield UploadProgress(
        phase: UploadPhase.generatingManifest,
        message: 'Generating manifest...',
        overallProgress: 0.95,
        successCount: successfulFiles.length,
        failedCount: totalFailedCount,
      );

      final manifest = GalleryManifest(
        eventName: config.eventName,
        createdAt: DateTime.now(),
        totalPhotos: successfulFiles.length,
        photos: successfulFiles
            .map(
              (pf) => GalleryPhoto(
                name: pf.name,
                thumbKey: '$eventSlug/thumbs/${pf.name}.webp',
                previewKey: '$eventSlug/previews/${pf.name}.webp',
              ),
            )
            .toList(),
        driveFolderId: driveFolderId,
      );

      final manifestUrl = await _withRetry(
        action: () => _r2Service.uploadManifest(
          objectKey: '$eventSlug/manifest.json',
          manifest: manifest.toJson(),
        ),
        isRetryable: _isRetryableR2,
      );

      stopwatch.stop();

      // ✅ FIX reviewer: Pesan konsisten dalam bahasa Inggris
      final completionMessage = totalFailedCount > 0
          ? 'Upload completed with $totalFailedCount file(s) failed.'
          : 'Upload complete!';

      yield UploadProgress(
        phase: UploadPhase.completed,
        totalFiles: totalFiles,
        currentFile: totalFiles,
        message: completionMessage,
        overallProgress: 1.0,
        galleryUrl: manifestUrl,
        successCount: successfulFiles.length,
        failedCount: totalFailedCount,
        totalDuration: stopwatch.elapsed,
      );
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  // ── Private helpers ──

  /// Scan folder untuk file gambar dengan batas keamanan dari [ScanLimits].
  ///
  /// ✅ FIX #3 Refactor: Delegasi ke [FileUtils.scanDirSync] — satu implementasi
  /// terpusat untuk semua scan logic. Tidak ada duplikasi dengan
  /// [FileOperationService.scanFolder] dan [FileOperationService.validateFiles].
  Future<List<File>> _scanForImages(
    String folderPath, {
    required bool recursive,
    required List<String> extensions,
  }) {
    final maxDepth = recursive ? ScanLimits.maxDepth : 0;
    return Isolate.run(() {
      final paths = FileUtils.scanDirSync(
        folderPath,
        extensions: extensions,
        maxDepth: maxDepth,
      );
      paths.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
      return paths;
    }).then((paths) => paths.map((path) => File(path)).toList());
  }

  Future<Directory> _createTempOutputDir() async {
    final appDir = await getTemporaryDirectory();
    final outputDir = Directory(
      p.join(appDir.path, 'hafiportrait_upload_temp'),
    );
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    return outputDir;
  }

  String _slugify(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<T> _withRetry<T>({
    required Future<T> Function() action,
    required bool Function(Object error) isRetryable,
  }) async {
    // Loop selalu rethrow di iterasi terakhir (canRetry = false),
    // sehingga baris setelah loop tidak pernah dicapai.
    for (var attempt = 0; attempt <= _retryOptions.maxRetries; attempt++) {
      try {
        return await action();
      } catch (e) {
        if (_isCancelled) rethrow;
        final canRetry = attempt < _retryOptions.maxRetries && isRetryable(e);
        if (!canRetry) rethrow;

        final delay = _retryDelay(attempt + 1);
        await Future.delayed(delay);
      }
    }
    // Unreachable — loop selalu rethrow sebelum sampai sini.
    // Diperlukan hanya agar Dart compiler puas dengan return type T.
    throw StateError('Unreachable: all retry attempts exhausted via rethrow');
  }

  Duration _retryDelay(int attempt) {
    final baseMs = _retryOptions.baseDelay.inMilliseconds.toDouble();
    final maxMs = _retryOptions.maxDelay.inMilliseconds.toDouble();
    final raw = baseMs * pow(_retryOptions.backoffFactor, attempt - 1);
    final capped = raw.clamp(baseMs, maxMs);

    // Jitter simetris: ±jitterRatio dari capped delay.
    // ✅ FIX: Clamp ke [0, maxMs] agar tidak pernah negatif atau melebihi max.
    // Sebelumnya: (capped + delta).round() bisa negatif jika delta > capped.
    final jitter = capped * _retryOptions.jitterRatio;
    final delta = (Random().nextDouble() * jitter * 2) - jitter;
    final ms = (capped + delta).clamp(0.0, maxMs).round();
    return Duration(milliseconds: ms);
  }

  bool _isRetryableR2(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('401') || msg.contains('403') || msg.contains('400')) {
      return false;
    }
    return _isTransientError(error);
  }

  bool _isRetryableDrive(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('invalid_grant') ||
        msg.contains('unauthorized') ||
        msg.contains('permission') ||
        msg.contains('401') ||
        msg.contains('403') ||
        msg.contains('404') ||
        msg.contains('400')) {
      return false;
    }
    return _isTransientError(error);
  }

  bool _isTransientError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('timed out') ||
        msg.contains('connection reset') ||
        msg.contains('connection closed') ||
        msg.contains('connection refused') ||
        msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('rate') ||
        msg.contains('throttle') ||
        msg.contains('500') ||
        msg.contains('502') ||
        msg.contains('503') ||
        msg.contains('504');
  }
}

class _RetryOptions {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final double backoffFactor;
  final double jitterRatio;

  const _RetryOptions({
    required this.maxRetries,
    required this.baseDelay,
    required this.maxDelay,
    required this.backoffFactor,
    required this.jitterRatio,
  });
}

/// Internal processed file data
class _ProcessedFile {
  final String sourcePath;
  final String thumbPath;
  final String previewPath;
  final String name;

  const _ProcessedFile({
    required this.sourcePath,
    required this.thumbPath,
    required this.previewPath,
    required this.name,
  });
}
