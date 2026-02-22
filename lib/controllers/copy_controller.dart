// Controller untuk logika bisnis Copy Page.
//
// Memisahkan business logic dari UI widget [_MainScreenState]
// sehingga main_screen.dart hanya bertanggung jawab untuk rendering.
//
// Pattern: thin UI layer → controller → provider/service

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../constants/file_constants.dart';
import '../providers/copy_provider.dart';
import '../services/file_picker_adapter.dart';

/// Controller untuk semua aksi di Copy Page.
///
/// Di-instantiate oleh [_MainScreenState]. Menerima callback [addLog]
/// agar controller bisa menulis ke log UI tanpa memegang referensi ke widget.
///
/// ✅ FIX reviewer: [WidgetRef] TIDAK disimpan sebagai field — ini anti-pattern
/// Riverpod karena ref bisa menjadi stale jika widget tree rebuild.
/// Setiap method menerima [WidgetRef] sebagai parameter agar selalu
/// menggunakan ref yang fresh dari widget scope.
class CopyController {
  final void Function(String message) addLog;

  CopyController({required this.addLog});

  /// Buka dialog pilih folder sumber
  Future<void> selectSourceFolder(WidgetRef ref) async {
    final picker = ref.read(filePickerProvider);
    final result = await picker.getDirectoryPath(
      dialogTitle: 'Select Source Folder',
    );
    if (result != null) {
      ref.read(copyProvider.notifier).setSourceFolder(result);
      addLog('📂 Source: $result');
    }
  }

  /// Import file names dari .txt atau .csv
  Future<String?> importFile(WidgetRef ref) async {
    final picker = ref.read(filePickerProvider);
    final result = await picker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final names = _parseFileNames(content);
      ref.read(copyProvider.notifier).setFileNames(names);
      addLog('📄 Imported ${names.length} file names');
      return content;
    }
    return null;
  }

  /// Paste file names dari clipboard
  Future<String?> pasteFromClipboard(WidgetRef ref) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      final names = _parseFileNames(data!.text!);
      ref.read(copyProvider.notifier).setFileNames(names);
      addLog('📋 Pasted ${names.length} names');
      return data.text;
    }
    return null;
  }

  /// Scan folder sumber dan isi file list otomatis
  Future<List<String>?> scanFolder(WidgetRef ref, String sourceFolder) async {
    if (sourceFolder.isEmpty) {
      addLog('⚠️ Select a source folder first');
      return null;
    }
    addLog('🔍 Scanning...');
    final service = ref.read(fileOperationServiceProvider);
    final files = await service.scanFolder(sourceFolder);
    final names = files
        .map((f) {
          final dot = f.name.lastIndexOf('.');
          return dot >= 0 ? f.name.substring(0, dot) : f.name;
        })
        .toSet()
        .toList();
    ref.read(copyProvider.notifier).setFileNames(names);
    addLog('✅ Found ${files.length} files (${names.length} unique)');
    return names;
  }

  /// Validasi file names terhadap source folder
  Future<void> validateFiles(WidgetRef ref) async {
    addLog('🔍 Validating...');
    await ref.read(copyProvider.notifier).validateFiles();
    final state = ref.read(copyProvider);
    addLog(
      '✅ ${state.validFiles.length} valid, '
      '${state.invalidFiles.length} not found',
    );
  }

  /// Mulai operasi copy
  Future<void> startCopy(WidgetRef ref) async {
    addLog('🚀 Starting copy...');
    await ref.read(copyProvider.notifier).startCopy();
    final state = ref.read(copyProvider);
    if (state.status == CopyStatus.completed) {
      addLog('✅ Done! ${state.result?.performanceGrade ?? ""}');
    } else if (state.status == CopyStatus.idle) {
      addLog('❌ Copy cancelled');
    }
  }

  /// Toggle pause/resume
  void togglePause(WidgetRef ref) {
    final notifier = ref.read(copyProvider.notifier);
    if (notifier.isPaused) {
      notifier.resumeCopy();
      addLog('▶️ Resumed');
    } else {
      notifier.pauseCopy();
      addLog('⏸ Paused');
    }
  }

  /// Cancel operasi copy
  void cancelCopy(WidgetRef ref) {
    ref.read(copyProvider.notifier).cancelCopy();
    addLog('❌ Cancelled');
  }

  /// Handle drag-and-drop files/folder ke app.
  ///
  /// - Folder → set sebagai source folder
  /// - .txt   → parse sebagai file names
  /// - Image  → extract nama file tanpa ekstensi
  ///
  /// Mengembalikan konten text area yang sudah diupdate, atau null jika
  /// tidak ada perubahan.
  Future<String?> handleDrop({
    required WidgetRef ref,
    required DropDoneDetails details,
    required String currentTextContent,
  }) async {
    final files = details.files;
    if (files.isEmpty) return null;

    // Gunakan kScanExtensions dari file_constants.dart — single source of truth
    final imageExtensions = kScanExtensions.toSet();
    final buffer = StringBuffer(currentTextContent);
    bool changed = false;

    for (final xFile in files) {
      final path = xFile.path;
      final entity = FileSystemEntity.typeSync(path);

      if (entity == FileSystemEntityType.directory) {
        ref.read(copyProvider.notifier).setSourceFolder(path);
        addLog('📁 Source folder set: $path');
        continue;
      }

      final ext = path.split('.').last.toLowerCase();

      if (ext == 'txt' || ext == 'csv') {
        try {
          final contents = await File(path).readAsString();
          final names = _parseFileNames(contents);
          if (names.isNotEmpty) {
            if (buffer.isNotEmpty) buffer.write('\n');
            buffer.write(names.join('\n'));
            addLog('📄 Imported ${names.length} names from ${ext.toUpperCase()}');
            changed = true;
          }
        } catch (e) {
          addLog('⚠️ Failed to read file: $e');
        }
        continue;
      }

      if (imageExtensions.contains(ext)) {
        final fileName = path.split(Platform.pathSeparator).last;
        final nameWithoutExt = fileName.contains('.')
            ? fileName.substring(0, fileName.lastIndexOf('.'))
            : fileName;
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(nameWithoutExt);
        addLog('🖼️ Added: $nameWithoutExt');
        changed = true;
      }
    }

    if (!changed) return null;

    final newContent = buffer.toString();
    final allNames = _parseFileNames(newContent);
    ref.read(copyProvider.notifier).setFileNames(allNames);
    return newContent;
  }

  // ── Private helpers ──

  /// Parse teks menjadi daftar nama file (satu per baris, trim whitespace)
  List<String> _parseFileNames(String text) {
    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }
}

/// Provider untuk [CopyController].
///
/// Di-create per widget dengan [CopyController(...)] langsung karena
/// membutuhkan [addLog] callback dari widget state.
/// Tidak perlu Riverpod provider karena controller bukan shared state.
