import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../theme/glass_colors.dart';
import '../widgets/glass_widgets.dart';
import '../providers/settings_provider.dart';
import '../models/cloud_account.dart';
import '../models/performance_settings.dart';

/// Settings page — app configuration
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _sectionHeader(context, 'Appearance', Icons.palette_rounded),
        const SizedBox(height: 12),
        _buildThemeCard(context, ref, settings),
        const SizedBox(height: 24),
        _sectionHeader(context, 'Copy Behavior', Icons.copy_rounded),
        const SizedBox(height: 12),
        _buildCopyBehaviorCard(context, ref, settings),
        const SizedBox(height: 24),
        _sectionHeader(
          context, 'Performance', Icons.speed_rounded,
        ),
        const SizedBox(height: 12),
        _buildPerformanceCard(context, ref, settings),
        const SizedBox(height: 24),
        _sectionHeader(
          context, 'Cloud Accounts', Icons.cloud_rounded,
        ),
        const SizedBox(height: 12),
        _buildCloudAccountsCard(context, ref, settings),
        const SizedBox(height: 24),
        _sectionHeader(context, 'About', Icons.info_outline_rounded),
        const SizedBox(height: 12),
        _buildAboutCard(context),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context, String title, IconData icon,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: GlassColors.liquidBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildThemeCard(
    BuildContext context, WidgetRef ref, SettingsState settings,
  ) {
    final isDark = settings.themeMode == ThemeMode.dark;
    return GlassCard(
      child: Row(
        children: [
          Icon(
            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            color: isDark
                ? GlassColors.liquidPurple
                : GlassColors.systemOrange,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text(
                  isDark ? 'Dark Mode' : 'Light Mode',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch(
            value: isDark,
            activeThumbColor: GlassColors.liquidPurple,
            onChanged: (_) {
              ref.read(settingsProvider.notifier).toggleTheme();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCopyBehaviorCard(
    BuildContext context, WidgetRef ref, SettingsState settings,
  ) {
    return GlassCard(
      child: Column(
        children: [
          // Skip existing
          _settingsRow(
            context,
            icon: Icons.skip_next_rounded,
            title: 'Skip Existing Files',
            subtitle: 'Skip files with same size at destination',
            trailing: Switch(
              value: settings.skipExistingFiles,
              activeThumbColor: GlassColors.liquidBlue,
              onChanged: (v) {
                ref.read(settingsProvider.notifier).setSkipExisting(v);
              },
            ),
          ),
          _divider(),
          // Duplicate handling
          _settingsRow(
            context,
            icon: Icons.content_copy_rounded,
            title: 'Duplicate Handling',
            subtitle: settings.duplicateHandling.name.toUpperCase(),
            trailing: DropdownButton<DuplicateHandling>(
              value: settings.duplicateHandling,
              dropdownColor: GlassColors.bgDarkTertiary,
              underline: const SizedBox.shrink(),
              style: const TextStyle(
                color: GlassColors.textDarkPrimary,
                fontSize: 13,
              ),
              items: DuplicateHandling.values
                  .map(
                    (h) => DropdownMenuItem(
                      value: h,
                      child: Text(h.name),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  ref
                      .read(settingsProvider.notifier)
                      .setDuplicateHandling(v);
                }
              },
            ),
          ),
          _divider(),
          // File extensions info
          _settingsRow(
            context,
            icon: Icons.extension_rounded,
            title: 'Supported Extensions',
            subtitle:
                'RAW: ${settings.rawExtensions.join(", ")}\n'
                'JPG: ${settings.jpgExtensions.join(", ")}',
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard(
    BuildContext context, WidgetRef ref, SettingsState settings,
  ) {
    return GlassCard(
      child: Column(
        children: [
          // Copy mode
          _settingsRow(
            context,
            icon: Icons.bolt_rounded,
            title: 'Copy Mode',
            subtitle: _copyModeDescription(settings.copyMode),
            trailing: DropdownButton<CopyMode>(
              value: settings.copyMode,
              dropdownColor: GlassColors.bgDarkTertiary,
              underline: const SizedBox.shrink(),
              style: const TextStyle(
                color: GlassColors.textDarkPrimary,
                fontSize: 13,
              ),
              items: CopyMode.values
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(m.name),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).setCopyMode(v);
                }
              },
            ),
          ),
          _divider(),
          // Parallelism slider
          _settingsRow(
            context,
            icon: Icons.tune_rounded,
            title: 'Max Parallelism',
            subtitle:
                '${settings.maxParallelism} threads '
                '(${Platform.numberOfProcessors} CPUs detected)',
          ),
          Slider(
            value: settings.maxParallelism.toDouble(),
            min: 1,
            max: Platform.numberOfProcessors.toDouble() * 3,
            divisions: Platform.numberOfProcessors * 3 - 1,
            activeColor: GlassColors.liquidTeal,
            label: '${settings.maxParallelism}',
            onChanged: (v) {
              ref
                  .read(settingsProvider.notifier)
                  .setMaxParallelism(v.toInt());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          _settingsRow(
            context,
            icon: Icons.info_outlined,
            title: 'Hafiportrait Manager',
            subtitle: 'Version 2.0.0\n'
                'Built with Flutter & Rust\n'
                '© 2026 Hafiportrait',
          ),
          _divider(),
          _settingsRow(
            context,
            icon: Icons.computer_rounded,
            title: 'System',
            subtitle:
                '${Platform.operatingSystem.toUpperCase()} '
                '${Platform.operatingSystemVersion}\n'
                '${Platform.numberOfProcessors} CPU cores',
          ),
        ],
      ),
    );
  }

  Widget _buildCloudAccountsCard(
    BuildContext context, WidgetRef ref, SettingsState settings,
  ) {
    final accounts = settings.r2Accounts;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // R2 accounts
          _settingsRow(
            context,
            icon: Icons.cloud,
            title: 'Cloudflare R2 Accounts',
            subtitle: '${accounts.length} configured',
            trailing: IconButton(
              icon: const Icon(Icons.add_circle, size: 20),
              color: GlassColors.liquidTeal,
              onPressed: () => _showAddR2Dialog(context, ref),
            ),
          ),
          if (accounts.isNotEmpty) ...
            accounts.map((a) => Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: Row(
                children: [
                  const Icon(Icons.storage, size: 14,
                      color: GlassColors.systemGray),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${a.name} — ${a.bucket}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 16),
                    color: GlassColors.systemGray,
                    onPressed: () {
                      ref.read(settingsProvider.notifier)
                          .removeR2Account(a.id);
                    },
                  ),
                ],
              ),
            )),
          _divider(),
          // Google Drive
          _settingsRow(
            context,
            icon: Icons.add_to_drive,
            title: 'Google Drive',
            subtitle: settings.googleDriveCredentialsPath ??
                'Not configured',
            trailing: IconButton(
              icon: Icon(
                settings.googleDriveCredentialsPath != null
                    ? Icons.check_circle
                    : Icons.folder_open,
                size: 20,
              ),
              color: settings.googleDriveCredentialsPath != null
                  ? GlassColors.liquidTeal
                  : GlassColors.systemGray,
              onPressed: () => _browseGDriveCredentials(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddR2Dialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final accountIdCtrl = TextEditingController();
    final accessKeyCtrl = TextEditingController();
    final secretKeyCtrl = TextEditingController();
    final bucketCtrl = TextEditingController();
    final publicUrlCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add R2 Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: accountIdCtrl,
                decoration: const InputDecoration(
                    labelText: 'Account ID'),
              ),
              TextField(
                controller: accessKeyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Access Key ID'),
              ),
              TextField(
                controller: secretKeyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Secret Access Key'),
                obscureText: true,
              ),
              TextField(
                controller: bucketCtrl,
                decoration: const InputDecoration(
                    labelText: 'Bucket Name'),
              ),
              TextField(
                controller: publicUrlCtrl,
                decoration: const InputDecoration(
                    labelText: 'Public URL (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final account = R2Account(
                id: DateTime.now()
                    .millisecondsSinceEpoch
                    .toString(),
                name: nameCtrl.text,
                accountId: accountIdCtrl.text,
                accessKey: accessKeyCtrl.text,
                secretKey: secretKeyCtrl.text,
                bucket: bucketCtrl.text,
                publicUrl: publicUrlCtrl.text,
              );
              ref.read(settingsProvider.notifier)
                  .addR2Account(account);
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _browseGDriveCredentials(
    BuildContext context, WidgetRef ref,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Google Drive credentials.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      ref.read(settingsProvider.notifier)
          .setGoogleDriveCredentialsPath(result.files.single.path!);
    }
  }

  Widget _settingsRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: GlassColors.systemGray),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.06),
      ),
    );
  }

  String _copyModeDescription(CopyMode mode) {
    return switch (mode) {
      CopyMode.standard => 'Safe, sequential copy',
      CopyMode.highPerformance => 'Parallel with buffered I/O',
      CopyMode.ultraFast => 'Memory-mapped + parallel',
    };
  }
}
