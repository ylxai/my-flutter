import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../theme/glass_colors.dart';
import '../widgets/glass_widgets.dart';
import '../providers/copy_provider.dart';
import '../models/file_item.dart';
import '../services/file_picker_adapter.dart';
import 'gallery_page.dart';
import 'publish_page.dart';
import 'settings_page.dart';

/// Main screen — Sidebar Layout C
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedNavIndex = 0;
  final TextEditingController _fileListController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  final List<String> _statusLogs = [];
  bool _isDragging = false;

  @override
  void dispose() {
    _fileListController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _statusLogs.add(
        '[${DateTime.now().toString().substring(11, 19)}] $message',
      );
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ─── Sidebar ───
          _buildSidebar(),
          // ─── Main Content ───
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // SIDEBAR
  // ═══════════════════════════════════════

  Widget _buildSidebar() {
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: GlassColors.sidebarBg,
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Logo
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/logo.png',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 24),
          // Nav items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                SidebarItem(
                  icon: Icons.content_copy_rounded,
                  label: 'Copy',
                  isActive: _selectedNavIndex == 0,
                  onTap: () => setState(() => _selectedNavIndex = 0),
                ),
                const SizedBox(height: 4),
                SidebarItem(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  isActive: _selectedNavIndex == 1,
                  onTap: () => setState(() => _selectedNavIndex = 1),
                ),
                const SizedBox(height: 4),
                SidebarItem(
                  icon: Icons.cloud_upload_rounded,
                  label: 'Publish',
                  isActive: _selectedNavIndex == 2,
                  onTap: () => setState(() => _selectedNavIndex = 2),
                ),
                const SizedBox(height: 4),
                SidebarItem(
                  icon: Icons.schedule_rounded,
                  label: 'Schedule',
                  isActive: _selectedNavIndex == 3,
                  onTap: () {
                    setState(() => _selectedNavIndex = 3);
                    _addLog('⏰ Scheduler — coming soon');
                  },
                ),
                const SizedBox(height: 4),
                SidebarItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'Reports',
                  isActive: _selectedNavIndex == 4,
                  onTap: () {
                    setState(() => _selectedNavIndex = 4);
                    _addLog('📊 Reports — coming soon');
                  },
                ),
              ],
            ),
          ),
          const Spacer(),
          // Settings at bottom
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SidebarItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              isActive: _selectedNavIndex == 5,
              onTap: () => setState(() => _selectedNavIndex = 5),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // MAIN CONTENT
  // ═══════════════════════════════════════

  Widget _buildContent() {
    return Container(
      color: GlassColors.bgDarkPrimary,
      child: Column(
        children: [
          // Title bar (always visible)
          _buildTitleBar(),
          // Page content
          Expanded(child: _buildPageBody()),
        ],
      ),
    );
  }

  Widget _buildPageBody() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildCopyPage();
      case 1:
        return const GalleryPage();
      case 2:
        return const PublishPage();
      case 5:
        return const SettingsPage();
      default:
        return _buildComingSoon();
    }
  }

  Widget _buildComingSoon() {
    final labels = [
      'Copy',
      'Gallery',
      'Publish',
      'Schedule',
      'Reports',
      'Settings',
    ];
    final label = _selectedNavIndex < labels.length
        ? labels[_selectedNavIndex]
        : 'Page';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 48,
            color: GlassColors.systemGray.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            '$label — coming soon',
            style: const TextStyle(color: GlassColors.systemGray, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyPage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          // Stats row
          Consumer(
            builder: (context, ref, _) {
              final stats = ref.watch(dashboardStatsProvider);
              return _buildStatsRow(stats);
            },
          ),
          const SizedBox(height: 16),
          // Main panels
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Source + File List
                Expanded(
                  flex: 5,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final copyState = ref.watch(copyProvider);
                      return _buildLeftPanel(copyState);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Right: Progress + Controls + Log
                Expanded(
                  flex: 3,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final copyState = ref.watch(copyProvider);
                      final stats = ref.watch(dashboardStatsProvider);
                      return _buildRightPanel(copyState, stats);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Status bar
          Consumer(
            builder: (context, ref, _) {
              final copyState = ref.watch(copyProvider);
              return _buildStatusBar(copyState);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      decoration: BoxDecoration(
        color: GlassColors.bgDarkSecondary,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          GradientText(
            'Hafiportrait Manager',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            gradient: GlassColors.accentGradient,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // STATS ROW
  // ═══════════════════════════════════════

  Widget _buildStatsRow(DashboardStats stats) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: StatCard(
              label: 'Files',
              value: '${stats.processedFiles}/${stats.totalFiles}',
              icon: Icons.insert_drive_file_rounded,
              accentColor: GlassColors.liquidBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              label: 'Speed',
              value: stats.speedMBps > 0
                  ? '${stats.speedMBps.toStringAsFixed(1)} MB/s'
                  : '-- MB/s',
              icon: Icons.speed_rounded,
              accentColor: GlassColors.liquidTeal,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              label: 'Elapsed',
              value: stats.elapsedTime,
              icon: Icons.timer_rounded,
              accentColor: GlassColors.liquidIndigo,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatCard(
              label: 'ETA',
              value: stats.eta,
              icon: Icons.hourglass_bottom_rounded,
              accentColor: GlassColors.liquidPurple,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // LEFT PANEL — Source + File List
  // ═══════════════════════════════════════

  Widget _buildLeftPanel(CopyState copyState) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _handleDrop(details);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: _isDragging
              ? Border.all(
                  color: GlassColors.liquidBlue.withValues(alpha: 0.6),
                  width: 2,
                )
              : null,
        ),
        child: Column(
          children: [
            _buildSourceCard(copyState),
            const SizedBox(height: 16),
            Expanded(child: _buildFileListCard(copyState)),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard(CopyState copyState) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_rounded,
                size: 18,
                color: GlassColors.liquidBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'Source Folder',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: GlassColors.bgDarkTertiary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Text(
                    copyState.sourceFolder.isEmpty
                        ? 'No folder selected...'
                        : copyState.sourceFolder,
                    style: TextStyle(
                      color: copyState.sourceFolder.isEmpty
                          ? GlassColors.systemGray
                          : GlassColors.textDarkPrimary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GlassButton(
                label: 'Browse',
                icon: Icons.folder_open_rounded,
                onPressed: _selectSourceFolder,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileListCard(CopyState copyState) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.list_alt_rounded,
                size: 18,
                color: GlassColors.liquidIndigo,
              ),
              const SizedBox(width: 8),
              Text('File List', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: GlassColors.bgDarkTertiary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_fileListController.text.split('\n').where((l) => l.trim().isNotEmpty).length} files',
                  style: const TextStyle(
                    fontSize: 11,
                    color: GlassColors.systemGray,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Text area
          Expanded(
            child: TextField(
              controller: _fileListController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: GlassColors.textDarkPrimary,
                height: 1.6,
              ),
              decoration: const InputDecoration(
                hintText: 'Enter file names (without ext), one per line...',
              ),
              onChanged: (value) {
                final names = value
                    .split('\n')
                    .where((l) => l.trim().isNotEmpty)
                    .map((l) => l.trim())
                    .toList();
                ref.read(copyProvider.notifier).setFileNames(names);
                setState(() {}); // update counter
              },
            ),
          ),
          const SizedBox(height: 12),
          // Actions row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              GlassButton(
                label: 'Import',
                icon: Icons.file_open_rounded,
                isPrimary: false,
                onPressed: _importFile,
              ),
              GlassButton(
                label: 'Paste',
                icon: Icons.content_paste_rounded,
                isPrimary: false,
                onPressed: _pasteFromClipboard,
              ),
              GlassButton(
                label: 'Scan',
                icon: Icons.search_rounded,
                isPrimary: false,
                onPressed: () => _scanFolder(copyState),
              ),
              GlassButton(
                label: 'Validate',
                icon: Icons.check_circle_outline_rounded,
                isLoading: copyState.status == CopyStatus.validating,
                color: GlassColors.liquidIndigo,
                onPressed: copyState.sourceFolder.isNotEmpty
                    ? () => _validateFiles()
                    : null,
              ),
            ],
          ),
          // Validation results
          if (copyState.validFiles.isNotEmpty ||
              copyState.invalidFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildValidationBanner(copyState),
          ],
        ],
      ),
    );
  }

  Widget _buildValidationBanner(CopyState copyState) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GlassColors.bgDarkTertiary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: GlassColors.systemGreen,
              ),
              const SizedBox(width: 6),
              Text(
                '${copyState.validFiles.length} valid',
                style: const TextStyle(
                  color: GlassColors.systemGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (copyState.invalidFiles.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: GlassColors.systemRed,
                ),
                const SizedBox(width: 4),
                Text(
                  '${copyState.invalidFiles.length} not found',
                  style: const TextStyle(
                    color: GlassColors.systemRed,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          if (copyState.duplicatesRemoved > 0)
            Text(
              '${copyState.duplicatesRemoved} dupes',
              style: const TextStyle(
                color: GlassColors.systemOrange,
                fontSize: 12,
              ),
            ),
          Text(
            FileItem.formatFileSize(
              copyState.validFiles.fold<int>(0, (s, f) => s + f.size),
            ),
            style: const TextStyle(
              color: GlassColors.systemGray2,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // RIGHT PANEL — Progress + Controls + Log
  // ═══════════════════════════════════════

  Widget _buildRightPanel(CopyState copyState, DashboardStats stats) {
    return Column(
      children: [
        _buildProgressCard(stats),
        const SizedBox(height: 16),
        _buildControlCard(copyState),
        const SizedBox(height: 16),
        Expanded(child: _buildLogCard()),
      ],
    );
  }

  Widget _buildProgressCard(DashboardStats stats) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Progress', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                '${stats.progressPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: GlassColors.liquidBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: stats.progressPercent / 100,
                backgroundColor: GlassColors.bgDarkTertiary,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  GlassColors.liquidBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${FileItem.formatFileSize(stats.bytesCopied)} / '
                '${FileItem.formatFileSize(stats.totalBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Row(
                children: [
                  _buildMiniStat(
                    '${stats.skippedFiles}',
                    'skip',
                    GlassColors.systemOrange,
                  ),
                  const SizedBox(width: 8),
                  _buildMiniStat(
                    '${stats.failedFiles}',
                    'fail',
                    GlassColors.systemRed,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String value, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$value $label', style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }

  Widget _buildControlCard(CopyState copyState) {
    final isCopying = copyState.status == CopyStatus.copying;
    final isPaused = copyState.status == CopyStatus.paused;
    final isActive = isCopying || isPaused;
    final hasValidFiles = copyState.validFiles.isNotEmpty;

    return GlassCard(
      child: Column(
        children: [
          // Start button
          SizedBox(
            width: double.infinity,
            child: GlassButton(
              label: isCopying
                  ? 'COPYING...'
                  : isPaused
                  ? 'PAUSED'
                  : 'START COPY',
              icon: isActive ? null : Icons.rocket_launch_rounded,
              isLoading: isCopying,
              onPressed: (!isActive && hasValidFiles) ? _startCopy : null,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: isPaused ? 'Resume' : 'Pause',
                  icon: isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  isPrimary: false,
                  color: isPaused ? GlassColors.systemGreen : null,
                  onPressed: isActive ? _togglePause : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassButton(
                  label: 'Cancel',
                  icon: Icons.stop_rounded,
                  isDestructive: true,
                  onPressed: isActive ? _cancelCopy : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.terminal_rounded,
                size: 16,
                color: GlassColors.systemGray,
              ),
              const SizedBox(width: 6),
              Text('Log', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (_statusLogs.isNotEmpty)
                InkWell(
                  onTap: () => setState(() => _statusLogs.clear()),
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 14,
                      color: GlassColors.systemGray,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: GlassColors.bgDarkTertiary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _statusLogs.isEmpty
                  ? const Center(
                      child: Text(
                        'No logs yet...',
                        style: TextStyle(
                          color: GlassColors.systemGray,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: _statusLogs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            _statusLogs[index],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: GlassColors.systemGray2,
                              height: 1.4,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // STATUS BAR
  // ═══════════════════════════════════════

  Widget _buildStatusBar(CopyState copyState) {
    String statusText;
    Color statusColor;

    switch (copyState.status) {
      case CopyStatus.idle:
        statusText = 'Ready';
        statusColor = GlassColors.systemGreen;
      case CopyStatus.validating:
        statusText = 'Validating...';
        statusColor = GlassColors.liquidBlue;
      case CopyStatus.copying:
        statusText = 'Copying: ${copyState.progress?.currentFileName ?? ""}';
        statusColor = GlassColors.liquidBlue;
      case CopyStatus.paused:
        statusText = 'Paused';
        statusColor = GlassColors.systemOrange;
      case CopyStatus.completed:
        statusText = 'Completed!';
        statusColor = GlassColors.systemGreen;
      case CopyStatus.error:
        statusText = 'Error: ${copyState.errorMessage ?? "Unknown"}';
        statusColor = GlassColors.systemRed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: GlassColors.bgDarkSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            '${Platform.operatingSystem.toUpperCase()} • Flutter',
            style: const TextStyle(color: GlassColors.systemGray, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════

  Future<void> _selectSourceFolder() async {
    final picker = ref.read(filePickerProvider);
    final result = await picker.getDirectoryPath(
      dialogTitle: 'Select Source Folder',
    );
    if (result != null) {
      ref.read(copyProvider.notifier).setSourceFolder(result);
      _addLog('📂 Source: $result');
    }
  }

  Future<void> _importFile() async {
    final picker = ref.read(filePickerProvider);
    final result = await picker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      _fileListController.text = content;
      final names = content
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.trim())
          .toList();
      ref.read(copyProvider.notifier).setFileNames(names);
      setState(() {});
      _addLog('📄 Imported ${names.length} file names');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _fileListController.text = data!.text!;
      final names = data.text!
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.trim())
          .toList();
      ref.read(copyProvider.notifier).setFileNames(names);
      setState(() {});
      _addLog('📋 Pasted ${names.length} names');
    }
  }

  Future<void> _scanFolder(CopyState copyState) async {
    if (copyState.sourceFolder.isEmpty) {
      _addLog('⚠️ Select a source folder first');
      return;
    }
    _addLog('🔍 Scanning...');
    final service = ref.read(fileOperationServiceProvider);
    final files = await service.scanFolder(copyState.sourceFolder);
    final names = files
        .map((f) {
          final name = f.name;
          final dot = name.lastIndexOf('.');
          return dot >= 0 ? name.substring(0, dot) : name;
        })
        .toSet()
        .toList();
    _fileListController.text = names.join('\n');
    ref.read(copyProvider.notifier).setFileNames(names);
    setState(() {});
    _addLog('✅ Found ${files.length} files (${names.length} unique)');
  }

  Future<void> _validateFiles() async {
    _addLog('🔍 Validating...');
    await ref.read(copyProvider.notifier).validateFiles();
    final state = ref.read(copyProvider);
    _addLog(
      '✅ ${state.validFiles.length} valid, '
      '${state.invalidFiles.length} not found',
    );
  }

  Future<void> _startCopy() async {
    _addLog('🚀 Starting copy...');
    await ref.read(copyProvider.notifier).startCopy();
    final state = ref.read(copyProvider);
    if (state.status == CopyStatus.completed) {
      _addLog('✅ Done! ${state.result?.performanceGrade ?? ""}');
    } else if (state.status == CopyStatus.idle) {
      _addLog('❌ Copy cancelled');
    }
  }

  void _togglePause() {
    final notifier = ref.read(copyProvider.notifier);
    if (notifier.isPaused) {
      notifier.resumeCopy();
      _addLog('▶️ Resumed');
    } else {
      notifier.pauseCopy();
      _addLog('⏸ Paused');
    }
  }

  void _cancelCopy() {
    ref.read(copyProvider.notifier).cancelCopy();
    _addLog('❌ Cancelled');
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    final files = details.files;
    if (files.isEmpty) return;

    final imageExtensions = {
      'cr2',
      'cr3',
      'nef',
      'arw',
      'raf',
      'orf',
      'rw2',
      'dng',
      'raw',
      'pef',
      'srw',
      'jpg',
      'jpeg',
      'png',
    };

    for (final xFile in files) {
      final path = xFile.path;
      final entity = FileSystemEntity.typeSync(path);

      if (entity == FileSystemEntityType.directory) {
        // Dropped a folder → set as source
        ref.read(copyProvider.notifier).setSourceFolder(path);
        _addLog('📁 Source folder set: $path');
        continue;
      }

      final ext = path.split('.').last.toLowerCase();

      if (ext == 'txt') {
        // Dropped a .txt file → parse lines as file names
        try {
          final contents = await File(path).readAsString();
          final names = contents
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();

          if (names.isNotEmpty) {
            final existing = _fileListController.text;
            final separator = existing.isNotEmpty && !existing.endsWith('\n')
                ? '\n'
                : '';
            _fileListController.text = '$existing$separator${names.join('\n')}';
            ref
                .read(copyProvider.notifier)
                .setFileNames(
                  _fileListController.text
                      .split('\n')
                      .where((l) => l.trim().isNotEmpty)
                      .map((l) => l.trim())
                      .toList(),
                );
            _addLog('📄 Imported ${names.length} names from TXT');
            setState(() {}); // update counter
          }
        } catch (e) {
          _addLog('⚠️ Failed to read TXT: $e');
        }
        continue;
      }

      if (imageExtensions.contains(ext)) {
        // Dropped image file → extract name without extension
        final fileName = path.split(Platform.pathSeparator).last;
        final nameWithoutExt = fileName.contains('.')
            ? fileName.substring(0, fileName.lastIndexOf('.'))
            : fileName;

        final existing = _fileListController.text;
        final separator = existing.isNotEmpty && !existing.endsWith('\n')
            ? '\n'
            : '';
        _fileListController.text = '$existing$separator$nameWithoutExt';
        _addLog('🖼️ Added: $nameWithoutExt');
      }
    }

    // Sync file names to provider
    final allNames = _fileListController.text
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim())
        .toList();
    ref.read(copyProvider.notifier).setFileNames(allNames);
    setState(() {});
  }
}
