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

import '../models/cloud_account.dart';
import '../src/rust/api.dart' as rust;
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

    final scannedFiles = await _scanForImages(
      config.sourceFolder,
      recursive: config.recursiveScan,
      extensions: config.extensions,
    );
    if (_isCancelled) return;
    yield UploadProgress(
      phase: UploadPhase.scanning,
      currentFile: scannedFiles.length,
      totalFiles: scannedFiles.length,
      message: 'Found ${scannedFiles.length} files',
      overallProgress: 0.05,
    );
    final imageFiles = scannedFiles
        .where((f) => _isProcessableImage(f.path))
        .toList();
    if (imageFiles.isEmpty) {
      yield const UploadProgress(
        phase: UploadPhase.error,
        message: 'No image files found in source folder.',
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

      final failed = results.where((r) => !r.success).toList();
      if (failed.isNotEmpty) {
        final failedName = p.basename(failed.first.sourcePath);
        yield UploadProgress(
          phase: UploadPhase.error,
          message: 'Processing failed: $failedName',
        );
        return;
      }

      final processedFiles = results
          .map(
            (r) => _ProcessedFile(
              sourcePath: r.sourcePath,
              thumbPath: r.thumbPath,
              previewPath: r.previewPath,
              name: p.basenameWithoutExtension(r.sourcePath),
            ),
          )
          .toList();

      yield UploadProgress(
        phase: UploadPhase.processing,
        currentFile: totalFiles,
        totalFiles: totalFiles,
        message: 'Processing complete',
        overallProgress: 0.3,
      );

      // Phase 3: Upload to R2
      // ✅ FIX P1-1: Continue-on-error — jangan abort seluruh batch jika
      // 1 file gagal. Kumpulkan semua error, lanjutkan file berikutnya.
      final eventSlug = _slugify(config.eventName);
      int uploadedR2 = 0;
      int r2FailedCount = 0;
      final r2Errors = <String>[];
      final successfulFiles = <_ProcessedFile>[];

      for (final pf in processedFiles) {
        if (_isCancelled) return;

        uploadedR2++;
        yield UploadProgress(
          phase: UploadPhase.uploadingToR2,
          currentFile: uploadedR2,
          totalFiles: totalFiles * 2,
          currentFileName: '${pf.name}.webp',
          message: 'Uploading to R2 $uploadedR2/${totalFiles * 2}...',
          overallProgress: 0.3 + (uploadedR2 / (totalFiles * 2)) * 0.4,
          failedCount: r2FailedCount,
        );

        bool fileSuccess = true;
        try {
          // Upload thumbnail
          await _withRetry(
            action: () => _r2Service.uploadFile(
              filePath: pf.thumbPath,
              objectKey: '$eventSlug/thumbs/${pf.name}.webp',
              contentType: 'image/webp',
            ),
            isRetryable: _isRetryableR2,
          );

          uploadedR2++;

          // Upload preview
          await _withRetry(
            action: () => _r2Service.uploadFile(
              filePath: pf.previewPath,
              objectKey: '$eventSlug/previews/${pf.name}.webp',
              contentType: 'image/webp',
            ),
            isRetryable: _isRetryableR2,
          );
        } catch (e) {
          // Catat error tapi lanjutkan file berikutnya
          r2FailedCount++;
          fileSuccess = false;
          r2Errors.add('${pf.name}: $e');
        }

        if (fileSuccess) {
          successfulFiles.add(pf);
        }
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

        final driveFiles = scannedFiles;
        final folderId = driveFolderId;
        if (folderId == null) {
          yield const UploadProgress(
            phase: UploadPhase.error,
            message: 'Drive folder id missing after creation',
          );
          return;
        }
        // ✅ FIX P1-1: Continue-on-error untuk Drive upload juga.
        // Gagal upload 1 file ke Drive tidak harus abort seluruh pipeline.
        int driveFailedCount = 0;
        for (int i = 0; i < driveFiles.length; i++) {
          if (_isCancelled) return;

          yield UploadProgress(
            phase: UploadPhase.uploadingToDrive,
            currentFile: i + 1,
            totalFiles: driveFiles.length,
            currentFileName: p.basename(driveFiles[i].path),
            message: 'Uploading to Drive ${i + 1}/${driveFiles.length}...',
            overallProgress: 0.7 + ((i + 1) / driveFiles.length) * 0.25,
            failedCount: driveFailedCount,
          );

          try {
            await _withRetry(
              action: () => _driveService.uploadFile(
                filePath: driveFiles[i].path,
                folderId: folderId,
              ),
              isRetryable: _isRetryableDrive,
            );
          } catch (e) {
            // Catat error Drive tapi lanjutkan file berikutnya
            driveFailedCount++;
          }
        }
      }

      // Phase 5: Generate and upload manifest
      // ✅ FIX P1-1: Manifest hanya berisi file yang berhasil di-upload ke R2,
      // bukan semua processedFiles (beberapa mungkin gagal upload).
      yield UploadProgress(
        phase: UploadPhase.generatingManifest,
        message: 'Generating manifest...',
        overallProgress: 0.95,
        successCount: successfulFiles.length,
        failedCount: r2FailedCount,
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

      // Pesan berbeda jika ada file yang gagal vs semua sukses
      final completionMessage = r2FailedCount > 0
          ? 'Upload selesai dengan $r2FailedCount file gagal.'
          : 'Upload complete!';

      yield UploadProgress(
        phase: UploadPhase.completed,
        totalFiles: totalFiles,
        currentFile: totalFiles,
        message: completionMessage,
        overallProgress: 1.0,
        galleryUrl: manifestUrl,
        successCount: successfulFiles.length,
        failedCount: r2FailedCount,
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

  Future<List<File>> _scanForImages(
    String folderPath, {
    required bool recursive,
    required List<String> extensions,
  }) {
    return Isolate.run(() {
      final dir = Directory(folderPath);
      if (!dir.existsSync()) return <String>[];

      final normalized = extensions
          .map((e) => e.toLowerCase().replaceFirst('.', ''))
          .toSet();
      final paths =
          dir
              .listSync(recursive: recursive, followLinks: false)
              .whereType<File>()
              .where((f) {
                final ext = p
                    .extension(f.path)
                    .toLowerCase()
                    .replaceFirst('.', '');
                return normalized.contains(ext);
              })
              .map((f) => f.path)
              .toList()
            ..sort((a, b) => p.basename(a).compareTo(p.basename(b)));
      return paths;
    }).then((paths) => paths.map((path) => File(path)).toList());
  }

  bool _isProcessableImage(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.jpg' || ext == '.jpeg' || ext == '.png';
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
    throw StateError('Retry failed');
  }

  Duration _retryDelay(int attempt) {
    final baseMs = _retryOptions.baseDelay.inMilliseconds.toDouble();
    final raw = baseMs * pow(_retryOptions.backoffFactor, attempt - 1);
    final capped = raw.clamp(
      baseMs,
      _retryOptions.maxDelay.inMilliseconds.toDouble(),
    );
    final jitter = capped * _retryOptions.jitterRatio;
    final delta = (Random().nextDouble() * jitter * 2) - jitter;
    final ms = (capped + delta).round();
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
