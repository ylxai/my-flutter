import 'file_item.dart';

/// Validation result after scanning files
class ValidationResult {
  final List<FileItem> validFiles;
  final List<InvalidFileItem> invalidFiles;
  final int duplicatesRemoved;

  const ValidationResult({
    this.validFiles = const [],
    this.invalidFiles = const [],
    this.duplicatesRemoved = 0,
  });

  int get totalSize => validFiles.fold<int>(0, (sum, f) => sum + f.size);

  String get formattedTotalSize => FileItem.formatFileSize(totalSize);
}

/// Result of a copy operation
class CopyResult {
  final List<FileItem> successfulFiles;
  final List<FailedFileItem> failedFiles;
  final List<FileItem> skippedFiles;
  final bool cancelled;
  final DateTime startTime;
  final DateTime? endTime;
  final double averageSpeedMBps;
  final double peakSpeedMBps;
  final int totalBytesTransferred;

  const CopyResult({
    this.successfulFiles = const [],
    this.failedFiles = const [],
    this.skippedFiles = const [],
    this.cancelled = false,
    required this.startTime,
    this.endTime,
    this.averageSpeedMBps = 0,
    this.peakSpeedMBps = 0,
    this.totalBytesTransferred = 0,
  });

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  String get performanceGrade {
    if (averageSpeedMBps > 200) return '🚀 ULTRA FAST';
    if (averageSpeedMBps > 100) return '⚡ VERY FAST';
    if (averageSpeedMBps > 50) return '🔥 FAST';
    if (averageSpeedMBps > 20) return '✅ GOOD';
    if (averageSpeedMBps > 5) return '🟡 MODERATE';
    return '⚠️ SLOW';
  }
}

/// Progress update during copy operations
class CopyProgress {
  final int totalFiles;
  final int processedFiles;
  final String currentFileName;
  final int bytesCopied;
  final int totalBytes;
  final double speedMBps;
  final int skippedCount;
  final int failedCount;
  final Duration elapsed;

  const CopyProgress({
    this.totalFiles = 0,
    this.processedFiles = 0,
    this.currentFileName = '',
    this.bytesCopied = 0,
    this.totalBytes = 0,
    this.speedMBps = 0,
    this.skippedCount = 0,
    this.failedCount = 0,
    this.elapsed = Duration.zero,
  });

  double get progressPercent =>
      totalFiles > 0 ? (processedFiles / totalFiles * 100) : 0;

  double get bytesProgressPercent =>
      totalBytes > 0 ? (bytesCopied / totalBytes * 100) : 0;

  String get speedDisplay => speedMBps >= 1024
      ? '${(speedMBps / 1024).toStringAsFixed(1)} GB/s'
      : '${speedMBps.toStringAsFixed(1)} MB/s';

  Duration get estimatedTimeRemaining {
    if (speedMBps <= 0 || totalBytes <= 0) return Duration.zero;
    final remainingBytes = totalBytes - bytesCopied;
    final remainingMB = remainingBytes / (1024 * 1024);
    final seconds = remainingMB / speedMBps;
    return Duration(seconds: seconds.toInt());
  }

  String get etaDisplay {
    final eta = estimatedTimeRemaining;
    if (eta == Duration.zero) return 'Menghitung...';
    final m = eta.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = eta.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s remaining';
  }
}
