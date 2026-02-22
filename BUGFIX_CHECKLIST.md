# 🛠️ Bug Fix Checklist — Production Readiness
**Branch:** `fix/production-readiness`
**Dibuat:** 2026-02-22
**Status Keseluruhan:** 🔴 In Progress

---

## 🚨 P0 — KRITIS (Harus selesai sebelum production)

- [x] **P0-1** — Race condition di parallel copy queue (`file_operation_service.dart` baris ~208) ✅ SELESAI
  - `ListQueue` diakses bersamaan oleh multiple worker tanpa sinkronisasi
  - Fix: Diganti dengan `_AtomicWorkQueue` (index-based, atomic dequeue) dan `_SafeCounter` (atomic increment)
  - `dart analyze` → No issues found

- [x] **P0-2** — `CopyResult` tidak mengisi `successfulFiles`, `failedFiles`, `skippedFiles` + provider tracking ✅ SELESAI
  - `startTime` dihitung salah (`DateTime.now().subtract(elapsed)`) — sudah difix
  - `successfulFiles`, `failedFiles`, `skippedFiles` selalu kosong meski copy selesai — sudah difix
  - Tambah tracking `skippedNames` & `failedNames` per-file selama stream berlangsung
  - Tambah dokumentasi provider `fileOperationServiceProvider` agar intent jelas
  - `dart analyze` → No issues found

- [x] **P0-3** — Ekstensi file terdefinisi di banyak tempat (duplikat konstanta) ✅ SELESAI
  - Buat `lib/constants/file_constants.dart` sebagai single source of truth
  - `kRawExtensions`, `kJpgExtensions`, `kExtraImageExtensions`, `kCopyExtensions`, `kScanExtensions`
  - Update `file_item.dart`, `file_operation_service.dart`, `settings_provider.dart` pakai konstanta terpusat
  - `dart analyze` → No issues found

- [x] **P0-4** — Directory scan tak terbatas tanpa max depth / max files / timeout ✅ SELESAI
  - Tambah class `ScanLimits` di `file_constants.dart` (maxDepth=10, maxFiles=50000, timeoutSeconds=60)
  - Ganti `listSync(recursive: true)` dengan rekursif manual berbatas depth di `scanFolder` dan `validateFiles`
  - Tambah try/catch per-direktori untuk skip folder yang tidak bisa diakses (permission denied)
  - Tambah try/catch per-file untuk skip file yang tidak bisa dibaca stat-nya
  - `dart analyze` → No issues found

---

## 🟠 P1 — PENTING (Selesaikan sebelum beta)

- [x] **P1-1** — Upload abort seluruh batch jika 1 file gagal ✅ SELESAI
  - Fix R2: continue-on-error, kumpulkan `r2Errors` + `r2FailedCount`, hanya abort jika SEMUA file gagal
  - Fix Drive: continue-on-error, catat `driveFailedCount`, lanjutkan file berikutnya
  - Manifest hanya berisi `successfulFiles` (bukan semua processedFiles)
  - Hasil akhir `UploadProgress.completed` berisi `successCount` + `failedCount` yang akurat
  - `dart analyze` → No issues found

- [x] **P1-2** — Google Drive query rentan injeksi nama folder ✅ SELESAI
  - Fix: Sanitasi `name` dengan escape `'` → `\'` dan `\` → `\\` sebelum dimasukkan ke query
  - Mengikuti Drive API query escape specification
  - `dart analyze` → No issues found

- [x] **P1-3** — Settings async load race condition ✅ SELESAI
  - Fix: Tambah flag `_isLoaded` + getter `isLoaded` di `SettingsNotifier`
  - Tambah `settingsLoadedProvider` — provider bool yang jadi `true` setelah `_load()` selesai
  - Wrap seluruh `_load()` dalam try/catch/finally — settings gagal load tidak crash app
  - State default tetap valid (pakai `kRawExtensions`/`kJpgExtensions` dari `file_constants.dart`)
  - `dart analyze` → No issues found

---

## 🔵 Post-Merge Fixes (Ditemukan saat review ulang)

- [x] **PM-1** — Retry jitter bisa negatif → `clamp(0.0, maxMs)` di `_retryDelay`
- [x] **PM-2** — `PauseController` mutex `.expect()` panic → `let Ok() else {}` + match graceful
- [x] **PM-3** — Double `ref.read(settingsProvider)` di `publish_page.dart` → baca sekali
- [x] **PM-4** — `R2Account.id` pakai timestamp → `Uuid().v4()`
- [x] **PM-5** — `async` tanpa `mounted` check di `settings_page.dart` → guard `!context.mounted`
- [x] **PM-6** — `_scanFolder` tidak handle error di `gallery_page.dart` → catch + SnackBar
- [x] **PM-7** — `'png'` hardcoded di `publish_page.dart` → `kExtraImageExtensions`
- [x] **PM-8** — Slider divisions off-by-one di `settings_page.dart` → `nCpu*2-1`

---

## 🟡 P2 — PENINGKATAN (Selesaikan sebelum release)

- [x] **P2-1** — `main_screen.dart` terlalu besar, logika UI campur bisnis ✅ SELESAI
  - Buat `lib/controllers/copy_controller.dart` — pisahkan semua business logic
  - `CopyController`: selectSourceFolder, importFile, pasteFromClipboard, scanFolder,
    validateFiles, startCopy, togglePause, cancelCopy, handleDrop
  - `_handleDrop` pakai `kScanExtensions` dari `file_constants.dart` — tidak hardcoded lagi
  - `main_screen.dart` actions tinggal 1 baris delegate ke controller
  - Tambah `if (!mounted) return` di `_addLog` — mencegah setState setelah dispose
  - `dart analyze` → No issues found

- [x] **P2-2** — Duplikasi logika decode di `process_image` vs `process_batch` (Rust) ✅ SELESAI
  - Ekstrak fungsi `decode_image()` terpusat di `image_processing.rs`
  - `process_image()` dan `process_batch()` keduanya pakai `decode_image()`
  - Hapus ~30 baris kode duplikat
  - Fix pre-existing Rust error: use of moved value di `copy_single_file` dan `compute_file_hash`
  - `cargo check` → Finished (hanya 1 warning unused import, bukan error)

- [x] **P2-3** — Directory scan tak terbatas ✅ SELESAI (dikerjakan di P0-4)

---

## ✅ Sudah Selesai

- **P0-1** — Race condition parallel copy queue → `_AtomicWorkQueue` + `_SafeCounter`
- **P0-2** — `CopyResult` field kosong + `startTime` salah hitung → tracking per-file + `startTime` direkam di awal
- **P0-3** — Duplikat ekstensi file → `lib/constants/file_constants.dart` sebagai single source of truth
- **P0-4** — Scan tak terbatas → rekursif manual dengan `ScanLimits` (maxDepth + maxFiles + error handling)
- **P1-1** — Upload abort on error → continue-on-error R2 + Drive, manifest hanya file sukses
- **P1-2** — Drive query injection → escape `'` dan `\` sebelum query
- **P1-3** — Settings race condition → `_isLoaded` flag + `settingsLoadedProvider` + try/catch/finally
- **P2-1** — `main_screen.dart` → `CopyController` controller terpisah + `kScanExtensions`
- **P2-2** — Duplikat decode Rust → `decode_image()` terpusat + fix pre-existing moved value errors
- **P2-3** — Scan tak terbatas → selesai di P0-4
- **PR Review** — 6 issue dari code reviewer diselesaikan:
  - `driveFailedCount` di-hoist ke outer scope → final `failedCount` include R2 + Drive
  - Pesan completion disamakan ke bahasa Inggris
  - `WidgetRef` dihapus dari field `CopyController` → di-pass per method
  - `ScanLimits` → `abstract final class` (Dart 3+ idiom, tidak bisa di-instantiate)
  - Tracking file berbasis nama → path identity (anti-collision)
  - `currentFilePath` ditambahkan ke `CopyProgress` untuk tracking akurat

---

## 📝 Catatan Progress

| Tanggal | Item | Keterangan |
|---------|------|------------|
| 2026-02-22 | P0-1 | Fix race condition `ListQueue` → `_AtomicWorkQueue` + `_SafeCounter`, dart analyze clean |
| 2026-02-22 | P0-2 | Fix `CopyResult` kosong, fix `startTime` salah, tambah tracking skipped/failed per-file, dart analyze clean |
| 2026-02-22 | P0-3 | Buat `file_constants.dart`, centralize semua ekstensi, dart analyze clean |
| 2026-02-22 | P0-4 | Fix scan tak terbatas → rekursif manual + ScanLimits + error handling, dart analyze clean |
| 2026-02-22 | P1-1 | Continue-on-error R2 + Drive, manifest dari successfulFiles, successCount/failedCount akurat |
| 2026-02-22 | P1-2 | Sanitasi nama folder Drive: escape single-quote dan backslash sebelum query |
| 2026-02-22 | P1-3 | Tambah `_isLoaded` flag, `settingsLoadedProvider`, wrap `_load()` dengan try/catch/finally |
| 2026-02-22 | P2-1 | Buat CopyController, pisahkan business logic dari main_screen.dart, pakai kScanExtensions |
| 2026-02-22 | P2-2 | Ekstrak decode_image() terpusat di Rust, fix pre-existing moved value errors di api.rs |
| 2026-02-22 | P2-3 | Sudah diselesaikan di P0-4 |
