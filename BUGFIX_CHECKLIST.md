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

- [ ] **P0-2** — `fileOperationServiceProvider` pakai `read` bukan `watch` di `copy_provider.dart`
  - Perubahan state tidak terpantau, UI tidak update
  - Fix: Ganti `ref.read` → `ref.watch` atau gunakan pola yang benar

- [ ] **P0-3** — Ekstensi file terdefinisi di banyak tempat (duplikat konstanta)
  - Fix: Centralize ke 1 file konstanta (`lib/constants/file_constants.dart`)

- [ ] **P0-4** — `CopyResult` tidak mengisi `successfulFiles` dan `failedFiles` dengan benar
  - Fix: Pastikan setiap operasi copy mengisi field tersebut

---

## 🟠 P1 — PENTING (Selesaikan sebelum beta)

- [ ] **P1-1** — Upload abort seluruh batch jika 1 file gagal (`upload_orchestrator.dart`)
  - Fix: Implementasi continue-on-error, kumpulkan semua error

- [ ] **P1-2** — Google Drive query rentan injeksi (`google_drive_upload_service.dart`)
  - Fix: Sanitasi input nama folder sebelum dipakai di query

- [ ] **P1-3** — Settings async load race condition (`settings_provider.dart`)
  - Fix: Pastikan settings fully loaded sebelum digunakan provider lain

---

## 🟡 P2 — PENINGKATAN (Selesaikan sebelum release)

- [ ] **P2-1** — `main_screen.dart` terlalu besar, logika UI campur bisnis
  - Fix: Refactor ke controller terpisah

- [ ] **P2-2** — Duplikasi `process_image` vs `process_batch` di Rust
  - Fix: Deduplikasi, gunakan satu fungsi generik

- [ ] **P2-3** — Directory scan tak terbatas (tanpa max depth / max files / timeout)
  - Fix: Tambahkan batas scan yang aman

---

## ✅ Sudah Selesai

- **P0-1** — Race condition parallel copy queue → `_AtomicWorkQueue` + `_SafeCounter`

---

## 📝 Catatan Progress

| Tanggal | Item | Keterangan |
|---------|------|------------|
| 2026-02-22 | P0-1 | Fix race condition `ListQueue` → `_AtomicWorkQueue` + `_SafeCounter`, dart analyze clean |
