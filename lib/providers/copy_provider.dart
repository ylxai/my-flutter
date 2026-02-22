import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/copy_result.dart';
import '../models/performance_settings.dart';
import '../providers/settings_provider.dart';
import '../services/file_operation_service.dart';

// ── Services ──

/// Provider untuk [FileOperationService].
///
/// Menggunakan [ref.watch] agar provider ini otomatis rebuild dan membuat
/// instance [FileOperationService] baru ketika settings (parallelism / copyMode)
/// berubah di [settingsProvider].
///
/// CATATAN: [FileOperationService] tidak boleh di-share antar operasi copy
/// yang berjalan bersamaan karena menyimpan state pause/cancel. Provider ini
/// selalu membuat instance baru saat settings berubah, yang sudah aman.
final fileOperationServiceProvider = Provider<FileOperationService>((ref) {
  final settings = ref.watch(settingsProvider);

  // Guard: jika settings belum selesai load (masih default), tetap gunakan
  // nilai yang ada — tidak perlu throw karena PerformanceSettings sudah
  // punya default value yang valid.
  final perf = PerformanceSettings(
    maxParallelism: settings.maxParallelism,
    mode: settings.copyMode,
  );
  return FileOperationService(settings: perf);
});

// ── Copy State ──

enum CopyStatus { idle, validating, copying, paused, completed, error }

class CopyState {
  final CopyStatus status;
  final String sourceFolder;
  final List<String> fileNames;
  final List<FileItem> validFiles;
  final List<InvalidFileItem> invalidFiles;
  final CopyProgress? progress;
  final CopyResult? result;
  final String? errorMessage;
  final int duplicatesRemoved;

  const CopyState({
    this.status = CopyStatus.idle,
    this.sourceFolder = '',
    this.fileNames = const [],
    this.validFiles = const [],
    this.invalidFiles = const [],
    this.progress,
    this.result,
    this.errorMessage,
    this.duplicatesRemoved = 0,
  });

  CopyState copyWith({
    CopyStatus? status,
    String? sourceFolder,
    List<String>? fileNames,
    List<FileItem>? validFiles,
    List<InvalidFileItem>? invalidFiles,
    CopyProgress? progress,
    CopyResult? result,
    String? errorMessage,
    int? duplicatesRemoved,
  }) {
    return CopyState(
      status: status ?? this.status,
      sourceFolder: sourceFolder ?? this.sourceFolder,
      fileNames: fileNames ?? this.fileNames,
      validFiles: validFiles ?? this.validFiles,
      invalidFiles: invalidFiles ?? this.invalidFiles,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      duplicatesRemoved: duplicatesRemoved ?? this.duplicatesRemoved,
    );
  }
}

class CopyNotifier extends Notifier<CopyState> {
  late FileOperationService _fileService;

  @override
  CopyState build() {
    _fileService = ref.watch(fileOperationServiceProvider);
    return const CopyState();
  }

  void setSourceFolder(String path) {
    state = state.copyWith(sourceFolder: path, status: CopyStatus.idle);
  }

  void setFileNames(List<String> names) {
    state = state.copyWith(fileNames: names);
  }

  Future<void> validateFiles() async {
    if (state.sourceFolder.isEmpty || state.fileNames.isEmpty) return;

    state = state.copyWith(status: CopyStatus.validating);

    try {
      final result = await _fileService.validateFiles(
        sourceFolder: state.sourceFolder,
        fileNames: state.fileNames,
      );

      state = state.copyWith(
        status: CopyStatus.idle,
        validFiles: result.validFiles,
        invalidFiles: result.invalidFiles,
        duplicatesRemoved: result.duplicatesRemoved,
      );
    } catch (e) {
      state = state.copyWith(
        status: CopyStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> startCopy({String? destinationFolder}) async {
    if (state.validFiles.isEmpty) return;

    final destFolder = destinationFolder ?? state.sourceFolder;
    final startTime = DateTime.now();
    state = state.copyWith(status: CopyStatus.copying);

    // Kumpulkan tracking per-file selama proses copy berlangsung.
    // Kita track nama file yang sudah diproses untuk bisa membagi
    // validFiles ke successfulFiles vs skippedFiles vs failedFiles.
    final skippedNames = <String>{};
    final failedNames = <String>{};

    try {
      final stream = _fileService.copyFiles(
        files: state.validFiles,
        destinationFolder: destFolder,
      );

      await for (final progress in stream) {
        // Reflect paused state from service
        final currentStatus = _fileService.isPaused
            ? CopyStatus.paused
            : CopyStatus.copying;

        // Track file yang diproses untuk kategorisasi hasil akhir
        final currentFile = progress.currentFileName;
        if (currentFile.isNotEmpty &&
            currentFile != '⏸ Paused' &&
            currentFile != 'Cancelled') {
          // Deteksi file yang di-skip: skippedCount naik tapi belum tercatat
          if (progress.skippedCount > skippedNames.length) {
            skippedNames.add(currentFile);
          }

          // Deteksi file yang gagal: failedCount naik tapi belum tercatat
          if (progress.failedCount > failedNames.length) {
            failedNames.add(currentFile);
          }
        }

        state = state.copyWith(progress: progress, status: currentStatus);
      }

      // Check if cancelled
      if (_fileService.isCancelled) {
        state = state.copyWith(status: CopyStatus.idle);
        return;
      }

      final lastProgress = state.progress;
      final endTime = DateTime.now();

      // ✅ FIX P0-2: Isi successfulFiles, failedFiles, skippedFiles
      // dengan benar berdasarkan tracking selama proses copy.
      final allFiles = state.validFiles;

      final failedFiles = allFiles
          .where((f) => failedNames.contains(f.name))
          .map(
            (f) => FailedFileItem(
              file: f,
              error: 'Copy failed — lihat log untuk detail',
            ),
          )
          .toList();

      final skippedFiles = allFiles
          .where((f) => skippedNames.contains(f.name))
          .toList();

      final successfulFiles = allFiles
          .where(
            (f) =>
                !failedNames.contains(f.name) &&
                !skippedNames.contains(f.name),
          )
          .toList();

      state = state.copyWith(
        status: CopyStatus.completed,
        result: CopyResult(
          startTime: startTime,
          endTime: endTime,
          averageSpeedMBps: lastProgress?.speedMBps ?? 0,
          totalBytesTransferred: lastProgress?.bytesCopied ?? 0,
          successfulFiles: successfulFiles,
          failedFiles: failedFiles,
          skippedFiles: skippedFiles,
          cancelled: false,
        ),
      );
    } catch (e) {
      state = state.copyWith(
        status: CopyStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void pauseCopy() {
    _fileService.pauseCopy();
    state = state.copyWith(status: CopyStatus.paused);
  }

  void resumeCopy() {
    _fileService.resumeCopy();
    state = state.copyWith(status: CopyStatus.copying);
  }

  void cancelCopy() {
    _fileService.cancelCopy();
    state = state.copyWith(status: CopyStatus.idle);
  }

  bool get isPaused => _fileService.isPaused;

  void reset() {
    state = const CopyState();
  }
}

final copyProvider = NotifierProvider<CopyNotifier, CopyState>(
  CopyNotifier.new,
);

// ── Dashboard Stats ──

class DashboardStats {
  final int totalFiles;
  final int processedFiles;
  final int skippedFiles;
  final int failedFiles;
  final double speedMBps;
  final String elapsedTime;
  final String eta;
  final double progressPercent;
  final int totalBytes;
  final int bytesCopied;

  const DashboardStats({
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.skippedFiles = 0,
    this.failedFiles = 0,
    this.speedMBps = 0,
    this.elapsedTime = '00:00',
    this.eta = '--:--',
    this.progressPercent = 0,
    this.totalBytes = 0,
    this.bytesCopied = 0,
  });
}

final dashboardStatsProvider = Provider<DashboardStats>((ref) {
  final state = ref.watch(copyProvider);
  final progress = state.progress;

  if (progress == null) return const DashboardStats();

  final elapsed = progress.elapsed;
  final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

  return DashboardStats(
    totalFiles: progress.totalFiles,
    processedFiles: progress.processedFiles,
    skippedFiles: progress.skippedCount,
    failedFiles: progress.failedCount,
    speedMBps: progress.speedMBps,
    elapsedTime: '$m:$s',
    eta: progress.etaDisplay,
    progressPercent: progress.bytesProgressPercent,
    totalBytes: progress.totalBytes,
    bytesCopied: progress.bytesCopied,
  );
});
