# Audit Report

Date: 2026-02-13

This report consolidates all previously identified findings, grouped by priority.

Priority key:
- P0: Critical (security/data loss/major correctness failure)
- P1: High (major functionality/performance impact)
- P2: Medium (performance, UX, maintainability)

## P0 — Critical

1) Upload pipeline uploads wrong data
- Path: `lib/services/upload_orchestrator.dart`
- Issue: Upload uses original files but names them `.webp` and sets `contentType: image/webp`; thumbnails/previews are not generated.
- Impact: Broken previews, incorrect MIME types, data mislabeling.
- Recommendation: Wire Rust image processing and upload actual WebP bytes; correct keys and content types.

2) Verification does not enforce failure
- Path: `rust/src/parallel.rs`
- Issue: Hash verification result is ignored; mismatches do not fail.
- Impact: Silent corruption risk.
- Recommendation: Propagate verification failures and mark file copy as failed.

3) Secrets exposure risk
- Paths: `credentials.json`, `lib/providers/settings_provider.dart`
- Issue: Credentials file in repo; R2 keys stored in plaintext SharedPreferences.
- Impact: Credential leakage.
- Recommendation: Remove secrets from repo, add to `.gitignore`, move to secure storage.

## P1 — High

4) Content-Type ignored on R2 uploads
- Path: `lib/services/r2_upload_service.dart`
- Issue: `contentType` parameter not used in `putObject`.
- Impact: Missing MIME metadata; incorrect rendering/caching.
- Recommendation: Pass `contentType` to R2 API metadata.

5) Rust image processing ignores quality settings
- Path: `rust/src/image_processing.rs`
- Issue: Always writes lossless WebP; ignores quality fields.
- Impact: Larger files, slower uploads.
- Recommendation: Use quality settings and non-lossless encoder as configured.

6) Upload scan misses nested files and RAWs
- Path: `lib/services/upload_orchestrator.dart`
- Issue: Non-recursive scan; limited extensions.
- Impact: Missing uploads for nested folders/RAWs.
- Recommendation: Make recursive scan configurable and include RAW extensions.

7) File validation is O(n*m) and can mis-match duplicates
- Path: `lib/services/file_operation_service.dart`
- Issue: Quadratic search; filename stem collisions overwrite entries.
- Impact: Slow validation; incorrect file matches.
- Recommendation: Use direct lookups and include extension/path in keys.

8) Copy performance settings are unused
- Paths: `lib/services/file_operation_service.dart`, `lib/providers/settings_provider.dart`
- Issue: `PerformanceSettings`/`maxParallelism` computed but never applied.
- Impact: Users cannot improve performance; UI settings are misleading.
- Recommendation: Apply settings in copy pipeline or remove them.

9) UI thread jank when reading dropped TXT
- Path: `lib/screens/main_screen.dart`
- Issue: `readAsStringSync()` in UI handler.
- Impact: UI freezes on large files.
- Recommendation: Use async read off main isolate.

10) Upload stats inaccurate
- Path: `lib/providers/upload_provider.dart`
- Issue: `successCount` uses current file count (double uploads); `failedCount` always 0; duration always 0.
- Impact: Misleading results.
- Recommendation: Track per-file outcomes and duration properly.

## P2 — Medium

11) Settings persistence gaps
- Path: `lib/providers/settings_provider.dart`
- Issue: `duplicateHandling`, `rawExtensions`, `jpgExtensions` not persisted; stale `googleDriveCredentialsPath`.
- Impact: Settings lost or stale after restart.
- Recommendation: Persist all fields and remove keys when null.

12) SharedPreferences writes are fire-and-forget
- Path: `lib/providers/settings_provider.dart`
- Issue: `_save()` not awaited.
- Impact: Potential write races and missed updates.
- Recommendation: Await saves or debounce.

13) History stored unbounded in SharedPreferences
- Path: `lib/providers/publish_history_provider.dart`
- Issue: Full history JSON stored in prefs with no cap.
- Impact: Startup slowdown, memory pressure.
- Recommendation: Cap list or move to file/DB.

14) JSON decode errors are swallowed
- Paths: `lib/providers/settings_provider.dart`, `lib/providers/publish_history_provider.dart`
- Issue: `catch (_) {}` ignores parsing errors.
- Impact: Silent data corruption; hard to debug.
- Recommendation: Log error and reset safely.

15) Skip-existing compares size only
- Path: `lib/services/file_operation_service.dart`
- Issue: Same-size file treated as identical.
- Impact: Modified files may be skipped.
- Recommendation: Optional checksum or timestamp comparison.

16) Upload logs can grow without bound
- Path: `lib/providers/upload_provider.dart`
- Issue: Log list grows on each progress update.
- Impact: Memory growth; UI rebuild cost.
- Recommendation: Cap log length or stream logs.

17) Gallery tile synchronous IO in build
- Path: `lib/screens/gallery_page.dart`
- Issue: `File.existsSync()` called per tile during build.
- Impact: UI jank on large galleries.
- Recommendation: Precompute asynchronously or cache results.

18) Profile writes are not atomic
- Path: `lib/services/profile_service.dart`
- Issue: Writes directly to `profiles.json`.
- Impact: Crash during write can corrupt file.
- Recommendation: Write to temp file, then rename.

19) CI lacks tests/analyze and caching
- Path: `.github/workflows/flutter_build.yml`
- Issue: No `flutter analyze` or tests; no caching.
- Impact: Regressions slip in; slower builds.
- Recommendation: Add analyze/tests and cache Flutter/Cargo artifacts.

20) Whole-page rebuilds on high-frequency state changes
- Path: `lib/screens/main_screen.dart`
- Issue: `ref.watch(copyProvider)` and `ref.watch(dashboardStatsProvider)` rebuild the entire Copy page on progress ticks.
- Impact: Unnecessary rebuild cost and UI jank on large operations.
- Recommendation: Use `select` and split into smaller `Consumer` widgets (progress/log sections).

21) Gallery rebuilds on unrelated CopyState updates
- Path: `lib/screens/gallery_page.dart`
- Issue: Watches full `CopyState` for `sourceFolder`.
- Impact: Gallery rebuilds on any copy progress/validation change.
- Recommendation: `ref.watch(copyProvider.select((s) => s.sourceFolder))`.

22) Publish page rebuilds for any upload log/progress update
- Path: `lib/screens/publish_page.dart`
- Issue: Watches full `uploadProvider`.
- Impact: Full page rebuilds on frequent progress/log updates.
- Recommendation: Split into sections and use `select` for each area.

23) App rebuilds for any settings change
- Path: `lib/app.dart`
- Issue: `ref.watch(settingsProvider)` causes `MaterialApp` rebuild on unrelated settings updates.
- Impact: Extra rebuilds; potential flicker.
- Recommendation: Watch only `themeMode` via `select`.

24) Gallery auto-scan does not react to source changes
- Path: `lib/screens/gallery_page.dart`
- Issue: `_autoScan()` runs only on init using `ref.read(copyProvider).sourceFolder`.
- Impact: Gallery can be stale if user changes source folder.
- Recommendation: `ref.listen` to source folder changes and re-scan.

25) Async loads without disposal guard
- Paths: `lib/providers/settings_provider.dart`, `lib/providers/publish_history_provider.dart`
- Issue: `_load()` updates state after async work; safe now but risky if providers become `autoDispose`.
- Impact: Potential setState-after-dispose in future refactors.
- Recommendation: Add mounted/disposed guards or keep providers non-autoDispose.

## Notes

- Rust performance engine exists but is underutilized in Dart flows.
- Several features appear partially implemented (upload image processing, performance settings).
