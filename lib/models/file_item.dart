/// File item model — represents a single file for copy operations
class FileItem {
  final String path;
  final String name;
  final int size;
  final DateTime? createdDate;
  final DateTime? modifiedDate;
  final String extension;

  FileItem({
    required this.path,
    required this.name,
    required this.size,
    this.createdDate,
    this.modifiedDate,
    String? extension,
  }) : extension = extension ?? _extractExtension(name);

  static String _extractExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  bool get isRaw => const [
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
  ].contains(extension);

  bool get isJpg => const ['jpg', 'jpeg'].contains(extension);

  bool get isImage =>
      isRaw ||
      isJpg ||
      const ['png', 'tiff', 'bmp', 'webp'].contains(extension);

  String get formattedSize => formatFileSize(size);

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String toString() => 'FileItem($name, $formattedSize)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileItem &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

/// Invalid file item — file not found or inaccessible
class InvalidFileItem {
  final String path;
  final String reason;

  const InvalidFileItem({required this.path, required this.reason});
}

/// Failed file item — file that failed to copy
class FailedFileItem {
  final FileItem file;
  final String error;

  const FailedFileItem({required this.file, required this.error});
}
