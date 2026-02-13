import 'package:flutter_test/flutter_test.dart';
import 'package:filecopy_utility/models/file_item.dart';

void main() {
  group('FileItem', () {
    test('should detect RAW extensions', () {
      final file = FileItem(path: '/test/photo.cr2', name: 'photo.cr2', size: 1024);
      expect(file.isRaw, isTrue);
      expect(file.isJpg, isFalse);
    });

    test('should detect JPG extensions', () {
      final file = FileItem(path: '/test/photo.jpg', name: 'photo.jpg', size: 1024);
      expect(file.isJpg, isTrue);
      expect(file.isRaw, isFalse);
    });

    test('should format file sizes correctly', () {
      expect(FileItem.formatFileSize(500), '500 B');
      expect(FileItem.formatFileSize(1024), '1.0 KB');
      expect(FileItem.formatFileSize(1048576), '1.0 MB');
      expect(FileItem.formatFileSize(1073741824), '1.00 GB');
    });

    test('should extract extension', () {
      final file = FileItem(path: '/test/photo.CR2', name: 'photo.CR2', size: 1024);
      expect(file.extension, 'cr2');
    });
  });
}
