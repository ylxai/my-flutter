import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class FilePickerAdapter {
  Future<String?> getDirectoryPath({String? dialogTitle});

  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  });
}

class DefaultFilePickerAdapter implements FilePickerAdapter {
  @override
  Future<String?> getDirectoryPath({String? dialogTitle}) {
    return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) {
    return FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
    );
  }
}

final filePickerProvider = Provider<FilePickerAdapter>((ref) {
  return DefaultFilePickerAdapter();
});
