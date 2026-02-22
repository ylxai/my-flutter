import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/glass_colors.dart';
import '../widgets/glass_widgets.dart';
import '../providers/copy_provider.dart';
import '../models/file_item.dart';

/// Gallery page state
final _galleryFilesProvider =
    NotifierProvider<_GalleryFilesNotifier, List<FileItem>>(
      _GalleryFilesNotifier.new,
    );

final _galleryLoadingProvider =
    NotifierProvider<_GalleryLoadingNotifier, bool>(
      _GalleryLoadingNotifier.new,
    );

class _GalleryFilesNotifier extends Notifier<List<FileItem>> {
  @override
  List<FileItem> build() => [];

  void setFiles(List<FileItem> files) => state = files;
}

class _GalleryLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool value) => state = value;
}

/// Gallery page — image grid browser
class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key});

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  ProviderSubscription<String>? _sourceFolderSub;

  @override
  void initState() {
    super.initState();
    // Auto-scan if source folder is set
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScan();
    });
    _sourceFolderSub = ref.listenManual<String>(
      copyProvider.select((s) => s.sourceFolder),
      (previous, next) {
        if (next.isNotEmpty && next != previous) {
          _scanFolder(next);
        }
      },
    );
  }

  @override
  void dispose() {
    _sourceFolderSub?.close();
    super.dispose();
  }

  void _autoScan() {
    final sourceFolder = ref.read(copyProvider).sourceFolder;
    if (sourceFolder.isNotEmpty) {
      _scanFolder(sourceFolder);
    }
  }

  Future<void> _scanFolder(String path) async {
    ref.read(_galleryLoadingProvider.notifier).setLoading(true);
    try {
      final service = ref.read(fileOperationServiceProvider);
      final files = await service.scanFolder(path);
      // Sort by modified date (newest first)
      files.sort((a, b) {
        final aDate = a.modifiedDate ?? DateTime(1970);
        final bDate = b.modifiedDate ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });
      ref.read(_galleryFilesProvider.notifier).setFiles(files);
    } finally {
      ref.read(_galleryLoadingProvider.notifier).setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = ref.watch(_galleryFilesProvider);
    final isLoading = ref.watch(_galleryLoadingProvider);
    final sourceFolder = ref.watch(copyProvider.select((s) => s.sourceFolder));

    return Column(
      children: [
        // Header
        _buildHeader(context, sourceFolder, files.length, isLoading),
        const SizedBox(height: 16),
        // Grid
        Expanded(
          child: isLoading
              ? _buildLoading()
              : files.isEmpty
              ? _buildEmpty(sourceFolder)
              : _buildGrid(files),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String sourceFolder,
    int fileCount,
    bool isLoading,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          const Icon(
            Icons.photo_library_rounded,
            color: GlassColors.liquidPurple,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            'Gallery',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          if (fileCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: GlassColors.liquidPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$fileCount files',
                style: const TextStyle(
                  color: GlassColors.liquidPurple,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          GlassButton(
            label: 'Refresh',
            icon: Icons.refresh_rounded,
            isPrimary: false,
            isLoading: isLoading,
            onPressed: sourceFolder.isNotEmpty
                ? () => _scanFolder(sourceFolder)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: GlassColors.liquidPurple),
          SizedBox(height: 16),
          Text(
            'Scanning folder...',
            style: TextStyle(color: GlassColors.systemGray),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(String sourceFolder) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_camera_rounded,
            size: 48,
            color: GlassColors.systemGray.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            sourceFolder.isEmpty
                ? 'Set a source folder first'
                : 'No image files found',
            style: const TextStyle(color: GlassColors.systemGray, fontSize: 14),
          ),
          if (sourceFolder.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Go to Copy page and browse for a folder',
              style: TextStyle(color: GlassColors.systemGray, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid(List<FileItem> files) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: files.length,
        itemBuilder: (context, index) {
          return _GalleryTile(file: files[index]);
        },
      ),
    );
  }
}

/// Single gallery tile
class _GalleryTile extends StatelessWidget {
  final FileItem file;

  const _GalleryTile({required this.file});

  @override
  Widget build(BuildContext context) {
    final isRaw = file.isRaw;
    final typeColor = isRaw ? GlassColors.liquidTeal : GlassColors.liquidBlue;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail placeholder
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    typeColor.withValues(alpha: 0.12),
                    typeColor.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // Image preview (JPG only)
                  if (!isRaw) _buildThumbnail(),
                  if (isRaw)
                    Center(
                      child: Icon(
                        Icons.raw_on_rounded,
                        size: 32,
                        color: typeColor.withValues(alpha: 0.5),
                      ),
                    ),
                  // Type badge
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isRaw ? 'RAW' : 'JPG',
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // File name
          Text(
            file.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // File info
          Text(
            FileItem.formatFileSize(file.size),
            style: const TextStyle(color: GlassColors.systemGray, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(file.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 200,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Icon(
            Icons.image_rounded,
            size: 28,
            color: GlassColors.liquidBlue.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
