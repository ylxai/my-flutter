// Upload state management provider.
//
// Manages the upload pipeline state using Riverpod.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cloud_account.dart';
import '../services/r2_upload_service.dart';
import '../services/google_drive_upload_service.dart';
import '../services/upload_orchestrator.dart';
import 'publish_history_provider.dart';

/// Current upload status
enum UploadStatus { idle, processing, uploading, completed, error, cancelled }

/// Single log entry during upload
class LogEntry {
  final DateTime timestamp;
  final String message;
  final LogLevel level;

  const LogEntry({
    required this.timestamp,
    required this.message,
    this.level = LogLevel.info,
  });
}

/// Log severity level
enum LogLevel { info, success, warning, error }

/// Upload state
class UploadState {
  final UploadStatus status;
  final UploadProgress? progress;
  final UploadResult? result;
  final String? errorMessage;
  final List<LogEntry> logs;

  const UploadState({
    this.status = UploadStatus.idle,
    this.progress,
    this.result,
    this.errorMessage,
    this.logs = const [],
  });

  UploadState copyWith({
    UploadStatus? status,
    UploadProgress? progress,
    UploadResult? result,
    String? errorMessage,
    List<LogEntry>? logs,
  }) {
    return UploadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      logs: logs ?? this.logs,
    );
  }
}

/// Upload state notifier
class UploadNotifier extends StateNotifier<UploadState> {
  final R2UploadService _r2Service;
  final GoogleDriveUploadService _driveService;
  final PublishHistoryNotifier _historyNotifier;
  UploadOrchestrator? _orchestrator;
  static const _maxLogs = 300;

  UploadNotifier({
    required R2UploadService r2Service,
    required GoogleDriveUploadService driveService,
    required PublishHistoryNotifier historyNotifier,
  }) : _r2Service = r2Service,
       _driveService = driveService,
       _historyNotifier = historyNotifier,
       super(const UploadState());

  void _addLog(String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      message: message,
      level: level,
    );
    final updated = [...state.logs, entry];
    state = state.copyWith(
      logs: updated.length > _maxLogs
          ? updated.sublist(updated.length - _maxLogs)
          : updated,
    );
  }

  /// Start the upload pipeline
  Future<void> startUpload(UploadConfig config) async {
    // Reset logs
    state = const UploadState(status: UploadStatus.processing);

    if (config.r2Account == null) {
      _addLog('No R2 account selected', level: LogLevel.error);
      state = state.copyWith(
        status: UploadStatus.error,
        errorMessage: 'No R2 account selected.',
      );
      return;
    }

    _addLog('Starting upload: ${config.eventName}');
    _addLog('R2 Account: ${config.r2Account!.name}');

    // Configure R2 service
    _r2Service.configure(config.r2Account!);

    // Test R2 connection
    _addLog('Testing R2 connection...');
    final connected = await _r2Service.testConnection();
    if (!connected) {
      _addLog('R2 connection failed', level: LogLevel.error);
      state = state.copyWith(
        status: UploadStatus.error,
        errorMessage: 'Cannot connect to R2. Check credentials.',
      );
      _saveToHistory(config, isSuccess: false);
      return;
    }
    _addLog('R2 connected ✓', level: LogLevel.success);

    // Authenticate Google Drive if needed
    if (config.uploadOriginalToDrive) {
      _addLog('Authenticating Google Drive...');
      if (config.googleDriveCredentialsPath == null) {
        _addLog('Drive credentials not set in Settings', level: LogLevel.error);
        // We continue, but Drive upload will fail or be skipped
      } else {
        try {
          await _driveService.authenticate(config.googleDriveCredentialsPath!);
          if (_driveService.isAuthenticated) {
            _addLog('Google Drive authenticated ✓', level: LogLevel.success);
          }
        } catch (e) {
          _addLog('Drive auth failed: $e', level: LogLevel.error);
          state = state.copyWith(
            status: UploadStatus.error,
            errorMessage: 'Drive auth failed: $e',
          );
          _saveToHistory(config, isSuccess: false);
          return;
        }
      }
    }

    // Create orchestrator
    _orchestrator = UploadOrchestrator(
      r2Service: _r2Service,
      driveService: _driveService,
    );

    try {
      await for (final progress in _orchestrator!.execute(config)) {
        if (progress.phase == UploadPhase.error) {
          _addLog(progress.message, level: LogLevel.error);
          state = state.copyWith(
            status: UploadStatus.error,
            errorMessage: progress.message,
          );
          _saveToHistory(config, isSuccess: false);
          return;
        }

        // Log phase transitions
        _logPhaseProgress(progress);

        if (progress.phase == UploadPhase.completed) {
          _addLog('Upload completed!', level: LogLevel.success);
          state = state.copyWith(
            status: UploadStatus.completed,
            progress: progress,
          );
          _saveToHistory(config, isSuccess: true, progress: progress);
          return;
        }

        final status = progress.phase == UploadPhase.processing
            ? UploadStatus.processing
            : UploadStatus.uploading;

        state = state.copyWith(status: status, progress: progress);
      }
    } catch (e) {
      _addLog('Error: $e', level: LogLevel.error);
      state = state.copyWith(
        status: UploadStatus.error,
        errorMessage: e.toString(),
      );
      _saveToHistory(config, isSuccess: false);
    }
  }

  void _logPhaseProgress(UploadProgress progress) {
    final msg = switch (progress.phase) {
      UploadPhase.scanning => 'Scanning files...',
      UploadPhase.processing =>
        'Processing ${progress.currentFile}/'
            '${progress.totalFiles}: '
            '${progress.currentFileName}',
      UploadPhase.uploadingToR2 =>
        'Uploading to R2 ${progress.currentFile}/'
            '${progress.totalFiles}: '
            '${progress.currentFileName}',
      UploadPhase.uploadingToDrive =>
        'Uploading to Drive ${progress.currentFile}/'
            '${progress.totalFiles}: '
            '${progress.currentFileName}',
      UploadPhase.generatingManifest => 'Generating manifest...',
      _ => null,
    };
    if (msg != null) {
      _addLog(msg);
    }
  }

  void _saveToHistory(
    UploadConfig config, {
    required bool isSuccess,
    UploadProgress? progress,
  }) {
    _historyNotifier.addRecord(
      PublishRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        eventName: config.eventName,
        publishedAt: DateTime.now(),
        photoCount: progress?.totalFiles ?? 0,
        successCount: progress?.successCount ?? 0,
        failedCount: progress?.failedCount ?? 0,
        duration: progress?.totalDuration ?? Duration.zero,
        galleryUrl: '',
        isSuccess: isSuccess,
      ),
    );
  }

  /// Cancel the upload
  void cancelUpload() {
    _orchestrator?.cancel();
    _addLog('Upload cancelled', level: LogLevel.warning);
    state = state.copyWith(status: UploadStatus.cancelled);
  }

  /// Reset to idle
  void reset() {
    state = const UploadState();
  }
}

/// Providers
final r2ServiceProvider = Provider<R2UploadService>((ref) {
  return R2UploadService();
});

final driveServiceProvider = Provider<GoogleDriveUploadService>((ref) {
  return GoogleDriveUploadService();
});

final uploadProvider = StateNotifierProvider<UploadNotifier, UploadState>((
  ref,
) {
  return UploadNotifier(
    r2Service: ref.watch(r2ServiceProvider),
    driveService: ref.watch(driveServiceProvider),
    historyNotifier: ref.watch(publishHistoryProvider.notifier),
  );
});
