// Publish page — upload gallery to R2 + Google Drive.
//
// Wizard-style UI: Setup → Progress → Result.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/cloud_account.dart';
import '../providers/settings_provider.dart';
import '../providers/upload_provider.dart';
import '../providers/publish_history_provider.dart';
import '../services/upload_orchestrator.dart';
import '../theme/glass_colors.dart';
import '../services/file_picker_adapter.dart';

class PublishPage extends ConsumerStatefulWidget {
  const PublishPage({super.key});

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  final _eventNameController = TextEditingController();
  String? _sourceFolder;
  R2Account? _selectedR2Account;
  bool _uploadOriginals = false;
  bool _scanRecursive = true;

  @override
  void dispose() {
    _eventNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(uploadProvider.select((s) => s.status));
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            '🌐 Publish to Web',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Upload gallery photos to cloud',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(153),
            ),
          ),
          const SizedBox(height: 24),

          // Content based on upload status
          Expanded(child: _buildContent(status, theme)),
        ],
      ),
    );
  }

  Widget _buildContent(UploadStatus status, ThemeData theme) {
    switch (status) {
      case UploadStatus.idle:
      case UploadStatus.cancelled:
        return Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(settingsProvider);
            return _buildSetupForm(settings, theme);
          },
        );
      case UploadStatus.processing:
      case UploadStatus.uploading:
        return Consumer(
          builder: (context, ref, _) {
            final progress = ref.watch(
              uploadProvider.select((s) => s.progress),
            );
            final logs = ref.watch(uploadProvider.select((s) => s.logs));
            return _buildProgressView(progress, logs, theme);
          },
        );
      case UploadStatus.completed:
        return Consumer(
          builder: (context, ref, _) {
            final progress = ref.watch(
              uploadProvider.select((s) => s.progress),
            );
            final logs = ref.watch(uploadProvider.select((s) => s.logs));
            return _buildResultView(progress, logs, theme);
          },
        );
      case UploadStatus.error:
        return Consumer(
          builder: (context, ref, _) {
            final progress = ref.watch(
              uploadProvider.select((s) => s.progress),
            );
            final logs = ref.watch(uploadProvider.select((s) => s.logs));
            final errorMessage = ref.watch(
              uploadProvider.select((s) => s.errorMessage),
            );
            return _buildErrorView(errorMessage, progress, logs, theme);
          },
        );
    }
  }

  // ── Setup Form ──

  Widget _buildSetupForm(SettingsState settings, ThemeData theme) {
    final accounts = settings.r2Accounts;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event Name
          _sectionTitle('Event Name', theme),
          const SizedBox(height: 8),
          TextField(
            controller: _eventNameController,
            decoration: InputDecoration(
              hintText: 'e.g. Wedding Budi & Ani',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.event, size: 20),
            ),
          ),
          const SizedBox(height: 20),

          // Source Folder
          _sectionTitle('Source Folder', theme),
          const SizedBox(height: 8),
          _buildFolderPicker(theme),
          const SizedBox(height: 12),
          _buildScanOptions(theme),
          const SizedBox(height: 20),

          // R2 Account
          _sectionTitle('Cloudflare R2 Account', theme),
          const SizedBox(height: 8),
          if (accounts.isEmpty)
            _buildNoAccountsCard(theme)
          else
            _buildAccountDropdown(accounts, theme),
          const SizedBox(height: 20),

          // Google Drive Toggle
          _buildDriveToggle(theme),
          const SizedBox(height: 32),

          // Publish Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _canPublish() ? _startPublish : null,
              icon: const Icon(Icons.cloud_upload, size: 20),
              label: const Text('Publish Gallery'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Published Gallery History
          _buildGalleryHistory(theme),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, ThemeData theme) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildFolderPicker(ThemeData theme) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickFolder,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withAlpha(128)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_open, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _sourceFolder ?? 'Select folder...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _sourceFolder != null
                      ? null
                      : theme.colorScheme.onSurface.withAlpha(128),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildNoAccountsCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.error.withAlpha(128)),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.error.withAlpha(20),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No R2 accounts configured.\n'
              'Go to Settings → Cloud Accounts.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOptions(ThemeData theme) {
    return Row(
      children: [
        Checkbox(
          value: _scanRecursive,
          onChanged: (value) {
            setState(() {
              _scanRecursive = value ?? true;
            });
          },
        ),
        Expanded(
          child: Text(
            'Scan subfolder (recursive)',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildAccountDropdown(List<R2Account> accounts, ThemeData theme) {
    return DropdownButtonFormField<R2Account>(
      initialValue: _selectedR2Account,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.cloud, size: 20),
      ),
      items: accounts
          .map(
            (a) => DropdownMenuItem(
              value: a,
              child: Text('${a.name} (${a.bucket})'),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() {
        _selectedR2Account = v;
      }),
      hint: const Text('Select R2 account'),
    );
  }

  Widget _buildDriveToggle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline.withAlpha(128)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SwitchListTile(
        title: const Text('Upload originals to Google Drive'),
        subtitle: const Text('15-20MB per file (optional)'),
        value: _uploadOriginals,
        onChanged: (v) => setState(() => _uploadOriginals = v),
        secondary: const Icon(Icons.add_to_drive, size: 24),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  // ── Progress View ──

  Widget _buildProgressView(
    UploadProgress? progress,
    List<LogEntry> logs,
    ThemeData theme,
  ) {
    if (progress == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _phaseIcon(progress.phase),
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(_phaseLabel(progress.phase), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(progress.message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        LinearProgressIndicator(
          value: progress.overallProgress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress.overallProgress * 100).toInt()}%',
          style: theme.textTheme.bodySmall,
        ),
        if (progress.totalFiles > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Step ${progress.currentFile}/${progress.totalFiles}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(170),
            ),
          ),
        ],
        if (progress.currentFileName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            progress.currentFileName,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(128),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            ref.read(uploadProvider.notifier).cancelUpload();
          },
          icon: const Icon(Icons.cancel, size: 18),
          label: const Text('Cancel'),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        ),
        const SizedBox(height: 16),
        // Log panel
        Expanded(child: _buildLogPanel(logs, theme)),
      ],
    );
  }

  // ── Result View ──

  Widget _buildResultView(
    UploadProgress? progress,
    List<LogEntry> logs,
    ThemeData theme,
  ) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle, size: 64, color: Colors.green.shade400),
        const SizedBox(height: 16),
        Text(
          'Gallery Published!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green.shade400,
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 12),
          Text(
            '${progress.totalFiles} photos uploaded',
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            ref.read(uploadProvider.notifier).reset();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Publish Another'),
        ),
        const SizedBox(height: 16),
        // Show log from this session
        Expanded(child: _buildLogPanel(logs, theme)),
      ],
    );
  }

  // ── Error View ──

  Widget _buildErrorView(
    String? errorMessage,
    UploadProgress? progress,
    List<LogEntry> logs,
    ThemeData theme,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            'Upload Failed',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ?? 'Unknown error',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              ref.read(uploadProvider.notifier).reset();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try Again'),
          ),
          if (progress != null) ...[
            const SizedBox(height: 16),
            SizedBox(height: 220, child: _buildLogPanel(logs, theme)),
          ],
        ],
      ),
    );
  }

  // ── Actions ──

  Future<void> _pickFolder() async {
    final picker = ref.read(filePickerProvider);
    final result = await picker.getDirectoryPath(
      dialogTitle: 'Select Photo Folder',
    );
    if (result != null) {
      setState(() {
        _sourceFolder = result;
        if (_eventNameController.text.isEmpty) {
          _eventNameController.text = p.basename(result);
        }
      });
    }
  }

  bool _canPublish() {
    return _eventNameController.text.isNotEmpty &&
        _sourceFolder != null &&
        _selectedR2Account != null;
  }

  void _startPublish() {
    final settings = ref.read(settingsProvider);
    final extensions = {
      ...settings.rawExtensions,
      ...settings.jpgExtensions,
      'png',
    }.map((e) => e.toLowerCase()).toList();
    final config = UploadConfig(
      eventName: _eventNameController.text,
      sourceFolder: _sourceFolder!,
      r2Account: _selectedR2Account,
      uploadOriginalToDrive: _uploadOriginals,
      googleDriveCredentialsPath: ref
          .read(settingsProvider)
          .googleDriveCredentialsPath,
      recursiveScan: _scanRecursive,
      extensions: extensions,
    );

    ref.read(uploadProvider.notifier).startUpload(config);
  }

  // ── Log Panel ──

  Widget _buildLogPanel(List<LogEntry> logs, ThemeData theme) {
    if (logs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Upload Log',
              style: theme.textTheme.labelMedium?.copyWith(
                color: GlassColors.systemGray,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: logs.length,
              itemBuilder: (_, i) {
                final log = logs[i];
                final color = switch (log.level) {
                  LogLevel.success => Colors.green.shade300,
                  LogLevel.warning => Colors.orange.shade300,
                  LogLevel.error => Colors.red.shade300,
                  _ => theme.colorScheme.onSurface.withAlpha(180),
                };
                final icon = switch (log.level) {
                  LogLevel.success => '✓',
                  LogLevel.warning => '⚠',
                  LogLevel.error => '✗',
                  _ => '·',
                };
                final time =
                    '${log.timestamp.hour.toString().padLeft(2, '0')}:'
                    '${log.timestamp.minute.toString().padLeft(2, '0')}:'
                    '${log.timestamp.second.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    '$time $icon ${log.message}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Gallery History ──

  Widget _buildGalleryHistory(ThemeData theme) {
    final history = ref.watch(publishHistoryProvider);
    if (history.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Published Galleries', theme),
        const SizedBox(height: 8),
        ...history.map((r) => _buildHistoryItem(r, theme)),
      ],
    );
  }

  Widget _buildHistoryItem(PublishRecord record, ThemeData theme) {
    final date =
        '${record.publishedAt.day}/${record.publishedAt.month}'
        '/${record.publishedAt.year} '
        '${record.publishedAt.hour.toString().padLeft(2, '0')}:'
        '${record.publishedAt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          Icon(
            record.isSuccess ? Icons.check_circle : Icons.error,
            size: 18,
            color: record.isSuccess
                ? Colors.green.shade400
                : Colors.red.shade400,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.eventName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$date · ${record.photoCount} photos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: GlassColors.systemGray,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16),
            color: GlassColors.systemGray,
            onPressed: () {
              ref.read(publishHistoryProvider.notifier).removeRecord(record.id);
            },
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  IconData _phaseIcon(UploadPhase phase) {
    switch (phase) {
      case UploadPhase.scanning:
        return Icons.search;
      case UploadPhase.processing:
        return Icons.auto_fix_high;
      case UploadPhase.uploadingToR2:
        return Icons.cloud_upload;
      case UploadPhase.uploadingToDrive:
        return Icons.add_to_drive;
      case UploadPhase.generatingManifest:
        return Icons.description;
      case UploadPhase.completed:
        return Icons.check_circle;
      case UploadPhase.error:
        return Icons.error;
    }
  }

  String _phaseLabel(UploadPhase phase) {
    switch (phase) {
      case UploadPhase.scanning:
        return 'Scanning...';
      case UploadPhase.processing:
        return 'Processing Images';
      case UploadPhase.uploadingToR2:
        return 'Uploading to R2';
      case UploadPhase.uploadingToDrive:
        return 'Uploading to Google Drive';
      case UploadPhase.generatingManifest:
        return 'Generating Manifest';
      case UploadPhase.completed:
        return 'Complete';
      case UploadPhase.error:
        return 'Error';
    }
  }
}
