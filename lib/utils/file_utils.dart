// Centralized file scanning utility.
//
// Sebelumnya logika scan ada di 2 tempat:
// - file_operation_service.dart (scanFolder + validateFiles)
// - upload_orchestrator.dart (_scanForImages)
//
// Keduanya memakai algoritma rekursif yang sama dengan ScanLimits yang sama.
// Dengan FileUtils, kedua service bisa memakai satu implementasi terpusat
// sehingga perubahan cukup dilakukan di satu tempat.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants/file_constants.dart';

/// Static utility class untuk operasi file yang dipakai lintas service.
abstract final class FileUtils {
  /// Scan folder secara rekursif dan kembalikan semua file yang cocok
  /// dengan [extensions] yang diberikan.
  ///
  /// Batas keamanan:
  /// - Maksimum [ScanLimits.maxDepth] level kedalaman
  /// - Maksimum [ScanLimits.maxFiles] file
  /// - Skip folder yang tidak bisa diakses (permission denied)
  /// - Skip file yang tidak bisa dibaca stat-nya
  ///
  /// [extensions] adalah list ekstensi tanpa titik, lowercase (e.g. `['jpg', 'cr2']`).
  /// Jika kosong, semua file dikembalikan.
  ///
  /// Fungsi ini didesain untuk dijalankan di dalam `Isolate.run()` karena
  /// menggunakan `listSync` — tidak boleh dipanggil langsung di UI thread.
  static List<String> scanDirSync(
    String folderPath, {
    required List<String> extensions,
    int maxDepth = ScanLimits.maxDepth,
    int maxFiles = ScanLimits.maxFiles,
  }) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    final normalized = extensions
        .map((e) => e.toLowerCase().replaceFirst('.', ''))
        .toSet();
    final results = <String>[];

    void scanDir(Directory current, int depth) {
      if (results.length >= maxFiles) return;

      List<FileSystemEntity> entries;
      try {
        entries = current.listSync(recursive: false, followLinks: false);
      } catch (_) {
        return; // Skip folder tanpa akses (permission denied)
      }

      for (final entry in entries) {
        if (results.length >= maxFiles) return;

        if (entry is File) {
          try {
            final ext = p
                .extension(entry.path)
                .toLowerCase()
                .replaceFirst('.', '');
            if (normalized.isEmpty || normalized.contains(ext)) {
              results.add(entry.path);
            }
          } catch (_) {
            // Skip file yang tidak bisa dibaca stat-nya
          }
        } else if (entry is Directory && depth < maxDepth) {
          scanDir(entry, depth + 1);
        }
      }
    }

    scanDir(dir, 0);
    return results;
  }
}
