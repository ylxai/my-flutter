# Production Readiness Review (Flutter Desktop + Rust FFI)

Date: 2026-02-22

Scope reviewed:
- Flutter/Dart UI, providers, services
- Rust core and FFI surfaces (flutter_rust_bridge)
- Desktop platform integration code (Linux/Windows runner)

## Executive Summary

The project shows strong momentum (Rust offloading exists, Riverpod is used, secure storage is introduced for R2 secrets), but it is **not yet production-grade** for a desktop deployment with strict reliability/security requirements.

Top blockers are:
1. **Critical concurrency bug in Dart copy queue** (race over `ListQueue` with parallel workers).
2. **Architecture split-brain**: production logic duplicated between Dart and Rust instead of one authoritative core.
3. **Weak path/ownership contracts at FFI boundary** (stringly-typed paths, no typed error model, no lifecycle docs).
4. **Potential DoS vectors from synchronous deep directory traversal in isolates** (unbounded scans, no cancellation).
5. **Observability and test coverage are insufficient for failure-prone paths** (copy, upload, retries, FFI edge cases).

---

## Findings by Priority

## P0 — Must fix before production

### 1) Data race in parallel copy queue (Dart)
- **Where:** `lib/services/file_operation_service.dart`
- **Issue:** Multiple async workers call `queue.removeFirst()` on a shared `ListQueue<FileItem>` without synchronization.
- **Why it matters:** This is undefined behavior at application level (interleaving between `isEmpty` and `removeFirst`) and can produce intermittent `StateError`, skipped files, or duplicate processing.
- **Recommendation:**
  - Use a `StreamQueue`/work channel pattern, or guard queue operations with a `Mutex` equivalent (single worker dispatcher + worker pool).
  - Better: remove Dart parallel copy path and route all batch copy through Rust where threading model is explicit.

### 2) Two competing copy engines create correctness drift
- **Where:** Dart `FileOperationService.copyFiles` vs Rust `copy_files_batch`/`copy_files_parallel`
- **Issue:** Core behavior exists in both languages (skip logic, progress, parallelism, cancellation), but with different semantics and failure handling.
- **Why it matters:** Production bugs emerge from divergence over time (e.g., hash verify behavior, skip rules, progress accounting). Hard to reason/test cross-platform.
- **Recommendation:**
  - Make Rust the single source of truth for copy/verify; Dart should orchestrate and render state only.
  - Keep one contract for progress events and one contract for terminal result.

### 3) FFI contract lacks strict ownership/error protocol
- **Where:** `rust/src/api.rs`, `lib/src/rust/api.dart`
- **Issue:** APIs return broad DTOs with `success + error_message` strings rather than typed error codes; no formal ownership/lifecycle doc for path normalization, temp outputs, cancellation state.
- **Why it matters:** String parsing errors and ambiguous ownership semantics become brittle in production and difficult to debug.
- **Recommendation:**
  - Define typed domain errors (`enum`) in Rust and bridge them explicitly.
  - Document ownership of all paths and temp directories at API level (caller vs callee responsibility).
  - Add contract tests for malformed paths, permission denied, cancellation timing.

### 4) Unbounded recursive scans with blocking sync filesystem calls
- **Where:** `validateFiles`, `scanFolder`, `_scanForImages`
- **Issue:** Uses `listSync(recursive: true)` and repeated `statSync()` heavily; while offloaded to isolates, scans are still unbounded and non-cancellable.
- **Why it matters:** On large/mounted/network filesystems this can stall pipeline and spike memory/CPU.
- **Recommendation:**
  - Move to streaming async iteration (`Directory.list`) with bounded batching.
  - Add cancellation token throughout scan + validation paths.
  - Add guardrails: max files, max depth (configurable), timeout/failsafe.

## P1 — High risk / major reliability gaps

### 5) Copy provider computes result metadata from last progress snapshot only
- **Where:** `lib/providers/copy_provider.dart`
- **Issue:** Final `CopyResult` derives duration/speed from `state.progress` after stream completion; edge cases can produce inaccurate metrics.
- **Recommendation:** Use explicit start/end timestamps and terminal summary emitted by copy engine, not inferred UI state.

### 6) Cancellation and pause are service-local, not operation-scoped
- **Where:** `FileOperationService` flags (`_isPaused`, `_isCancelled`)
- **Issue:** Mutable flags live in service instance and can be impacted by overlapping operations/ref rebuilds.
- **Recommendation:** Use immutable operation handle/session token per run; command pause/cancel by operation ID.

### 7) Hash API still exposes MD5 as first-class option
- **Where:** `rust/src/hash.rs`, `rust/src/api.rs`
- **Issue:** MD5 is not collision resistant and should not be used for security-sensitive integrity checks.
- **Recommendation:** Default and prefer SHA-256 only; keep MD5 only for legacy compatibility with explicit "non-security" labeling.

### 8) Upload pipeline aborts entire run on first file failure
- **Where:** `lib/services/upload_orchestrator.dart`
- **Issue:** Any single failed process/upload emits `UploadPhase.error` and returns.
- **Why it matters:** Non-resilient for large event batches.
- **Recommendation:** Continue-on-error mode with per-file failure collection and final report.

### 9) Insufficiently normalized/validated user-controlled paths
- **Where:** folder pick/drop/import flows + upload config
- **Issue:** Paths are mostly trusted; canonicalization/allowlist policy is inconsistent between Dart and Rust.
- **Recommendation:** enforce a centralized path policy module (symlink policy, traversal policy, allowed roots).

## P2 — Medium (maintainability/perf/clean architecture)

### 10) UI widget still contains significant orchestration logic
- **Where:** `lib/screens/main_screen.dart`
- **Issue:** Parsing dropped files, scanning, logging, and copy workflow control are handled in the view layer.
- **Recommendation:** Move workflow orchestration to use-cases/controllers; keep widget declarative.

### 11) Layering is not cleanly separated (presentation/domain/data)
- **Where:** `lib/` overall structure
- **Issue:** `screens`, `providers`, `services`, `models` coexist but domain boundaries are blurred; business rules in providers/services mixed with UI expectations.
- **Recommendation:** Adopt explicit layers:
  - `presentation/` (widgets/view-models)
  - `domain/` (entities, value objects, use cases, repository interfaces)
  - `data/` (repository impl, FFI adapters, cloud clients)

### 12) Progress/log updates may drive avoidable rebuild pressure
- **Where:** high-frequency provider watches in main/publish/gallery screens
- **Recommendation:** Increase `select` usage and isolate fast-changing widgets.

### 13) Missing API docs for Rust public functions and FFI DTO semantics
- **Where:** `rust/src/api.rs`, bridge DTOs
- **Recommendation:** Rustdoc each public API with invariants, thread-safety notes, ownership expectations.

---

## Security Review Notes

- Positive: R2 secrets now stored using `flutter_secure_storage` rather than plain prefs.
- Remaining concerns:
  - No explicit threat model for local filesystem attack surface (symbolic links, permission errors, TOCTOU during copy).
  - No audit trail/structured logging for sensitive operations and failures.
  - Path handling policy should be documented and tested across Windows/macOS/Linux path edge cases.

---

## Rust-Specific Assessment

Strengths:
- Uses `Result` broadly; avoids most `unwrap()` in operational paths.
- Hash verification failure is correctly converted to per-file failure in parallel copy flow.
- Unsafe mmap calls are wrapped with error handling and fallback.

Gaps:
- Global Rayon pool configured once; subsequent operations cannot adapt thread count dynamically.
- `CURRENT_OPERATION` global state model is fragile under concurrent consumers.
- DTO booleans + message strings are weak for long-term API evolution.

---

## C / Desktop Runner Assessment

- Only standard Flutter runner scaffolding appears present (`linux/runner`, `windows/runner`).
- No custom C buffer handling logic observed in app domain code.
- Still recommended: keep runner dependencies updated and enable compiler hardening flags in release builds.

---

## Testing Gaps (Production-critical)

### Add immediately
1. **Dart unit tests**
   - `FileOperationService.copyFiles` concurrency behavior (parallel workers).
   - Validation logic for duplicate stems and extension filters.
2. **Rust unit/integration tests**
   - `copy_files_parallel` cancel/pause/verify permutations.
   - Path canonicalization + symlink edge cases.
   - mmap fallback behavior under failure injection.
3. **FFI contract tests (integration)**
   - Cross-language marshaling for large path strings/non-UTF edge cases.
   - Error mapping stability (no string parsing in Dart).
4. **Desktop integration smoke tests**
   - Large directory scan/copy/upload runs on Windows/macOS/Linux CI matrix.

---

## Recommended Target Architecture

1. **Core domain in Rust (single authoritative engine)**
   - copy, verify, scan, image processing, and typed errors.
2. **Dart as orchestration + UX layer**
   - no file-copy business logic in widgets/services beyond coordination.
3. **Repository/adapters pattern in Dart**
   - `CopyRepository`, `UploadRepository` interfaces in domain.
   - FFI + cloud services only in data layer implementations.
4. **Operational safety controls**
   - operation IDs, cancellation tokens, structured logs, retry budgets, max-scan limits.

---

## Production Readiness Verdict

**Status: Not ready for production yet.**

If you resolve all P0 items and at least items 5–9 under P1, then this can realistically move into a controlled beta phase with confidence.
