/// Konstanta terpusat untuk ekstensi file yang didukung aplikasi.
///
/// Sebelumnya ekstensi didefinisikan di 4 tempat berbeda:
/// - `file_item.dart` (isRaw getter)
/// - `file_operation_service.dart` (validateFiles + scanFolder default params)
/// - `settings_provider.dart` (SettingsState default)
/// - `copy_provider.dart` (tidak langsung, via settings)
///
/// Dengan file ini semua definisi mengacu ke satu sumber kebenaran (single
/// source of truth), sehingga menambah format baru cukup di sini saja.
/// Ekstensi RAW camera yang didukung (lowercase, tanpa titik).
const List<String> kRawExtensions = [
  'cr2', // Canon
  'cr3', // Canon (generasi baru)
  'nef', // Nikon
  'arw', // Sony
  'raf', // Fujifilm
  'orf', // Olympus
  'rw2', // Panasonic
  'dng', // Adobe Digital Negative (universal)
  'raw', // Generic RAW
  'pef', // Pentax
  'srw', // Samsung
];

/// Ekstensi JPEG yang didukung (lowercase, tanpa titik).
const List<String> kJpgExtensions = ['jpg', 'jpeg'];

/// Ekstensi gambar tambahan yang didukung untuk scanning (bukan copy).
const List<String> kExtraImageExtensions = ['png', 'tiff', 'bmp', 'webp'];

/// Semua ekstensi yang valid untuk operasi copy (RAW + JPG).
const List<String> kCopyExtensions = [...kRawExtensions, ...kJpgExtensions];

/// Semua ekstensi yang valid untuk scanning folder (RAW + JPG + extra).
const List<String> kScanExtensions = [
  ...kRawExtensions,
  ...kJpgExtensions,
  ...kExtraImageExtensions,
];

/// Batas keamanan untuk operasi scan folder.
///
/// Mencegah hang / OOM jika user memilih folder sistem atau drive root.
///
/// Gunakan [abstract final class] agar tidak bisa di-instantiate secara
/// tidak sengaja — semua member adalah static const.
///
/// Hard stop dilakukan di dalam Isolate via [maxDepth] + [maxFiles].
/// Tidak ada timeout eksternal — Isolate berjalan di memori terpisah
/// sehingga `.timeout()` tidak bisa menghentikannya secara efektif.
abstract final class ScanLimits {
  /// Kedalaman direktori maksimum yang akan di-scan secara rekursif.
  /// Contoh: depth 10 artinya folder/a/b/c/d/e/f/g/h/i/j adalah level terdalam.
  static const int maxDepth = 10;

  /// Jumlah file maksimum yang dikembalikan dalam satu operasi scan.
  static const int maxFiles = 50000;
}
