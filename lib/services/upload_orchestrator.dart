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
      final eventSlug = _slugify(config.eventName);
      int uploadedR2 = 0;

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
        );

        try {
          // Upload thumbnail
          await _r2Service.uploadFile(
            filePath: pf.thumbPath,
            objectKey: '$eventSlug/thumbs/${pf.name}.webp',
            contentType: 'image/webp',
          );

          uploadedR2++;

          // Upload preview
          await _r2Service.uploadFile(
            filePath: pf.previewPath,
            objectKey: '$eventSlug/previews/${pf.name}.webp',
            contentType: 'image/webp',
          );
        } catch (e) {
          yield UploadProgress(
            phase: UploadPhase.error,
            message: 'R2 upload failed: ${pf.name} ($e)',
          );
          return;
        }
      }

      // Phase 4: Upload originals to Google Drive (if enabled)
      String? driveFolderId;
      if (config.uploadOriginalToDrive && _driveService.isAuthenticated) {
        try {
          driveFolderId = await _driveService.createFolder(config.eventName);
          await _driveService.makeFolderPublic(driveFolderId);
        } catch (e) {
          yield UploadProgress(
            phase: UploadPhase.error,
            message: 'Drive folder creation failed: $e',
          );
          return;
        }

        final driveFiles = scannedFiles;
        for (int i = 0; i < driveFiles.length; i++) {
          if (_isCancelled) return;

          yield UploadProgress(
            phase: UploadPhase.uploadingToDrive,
            currentFile: i + 1,
            totalFiles: driveFiles.length,
            currentFileName: p.basename(driveFiles[i].path),
            message: 'Uploading to Drive ${i + 1}/${driveFiles.length}...',
            overallProgress: 0.7 + ((i + 1) / driveFiles.length) * 0.25,
          );

          try {
            await _driveService.uploadFile(
              filePath: driveFiles[i].path,
              folderId: driveFolderId,
            );
          } catch (e) {
            yield UploadProgress(
              phase: UploadPhase.error,
              message:
                  'Drive upload failed: ${p.basename(driveFiles[i].path)} ($e)',
            );
            return;
          }
        }
      }

      // Phase 5: Generate and upload manifest
      yield UploadProgress(
        phase: UploadPhase.generatingManifest,
        message: 'Generating manifest...',
        overallProgress: 0.95,
      );

      final manifest = GalleryManifest(
        eventName: config.eventName,
        createdAt: DateTime.now(),
        totalPhotos: totalFiles,
        photos: processedFiles
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

      // Upload manifest — URL not used yet but will be for result
      final manifestUrl = await _r2Service.uploadManifest(
        objectKey: '$eventSlug/manifest.json',
        manifest: manifest.toJson(),
      );

      stopwatch.stop();

      yield UploadProgress(
        phase: UploadPhase.completed,
        totalFiles: totalFiles,
        currentFile: totalFiles,
        message: 'Upload complete!',
        overallProgress: 1.0,
        galleryUrl: manifestUrl,
        successCount: totalFiles,
        failedCount: 0,
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
