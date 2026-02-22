//! Flutter Rust Bridge API
//!
//! Public API exposed to Dart via flutter_rust_bridge.
//! All functions here are callable from Flutter.

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::sync::Mutex;

use crate::file_copy;
use crate::hash;
use crate::image_processing;
use crate::parallel;
use crate::path_utils;

// ── Data Transfer Objects (mirrored in Dart) ──

/// Single file copy result — sent to Dart
#[repr(C)]
#[derive(Debug, Clone)]
pub struct NativeFileCopyResult {
    pub source_path: String,
    pub dest_path: String,
    pub bytes_copied: u64,
    pub duration_ms: u64,
    pub speed_mbps: f64,
    pub strategy_used: String,
    pub success: bool,
    pub error_message: String,
    pub skipped: bool,
}

/// Batch copy result — sent to Dart
#[repr(C)]
#[derive(Debug, Clone)]
pub struct NativeBatchResult {
    pub results: Vec<NativeFileCopyResult>,
    pub total_bytes_copied: u64,
    pub total_files: u32,
    pub successful_count: u32,
    pub failed_count: u32,
    pub skipped_count: u32,
    pub total_duration_ms: u64,
    pub average_speed_mbps: f64,
    pub peak_speed_mbps: f64,
    pub cancelled: bool,
}

/// Progress update — streamed to Dart
#[repr(C)]
#[derive(Debug, Clone)]
pub struct NativeCopyProgress {
    pub total_files: u32,
    pub processed_files: u32,
    pub current_file: String,
    pub bytes_copied: u64,
    pub total_bytes: u64,
    pub speed_mbps: f64,
    pub skipped_count: u32,
    pub failed_count: u32,
}

/// File entry for batch operations — received from Dart
#[repr(C)]
#[derive(Debug, Clone)]
pub struct NativeFileEntry {
    pub source_path: String,
    pub dest_path: String,
    pub size: u64,
}

/// Hash verification result
#[repr(C)]
#[derive(Debug, Clone)]
pub struct NativeHashResult {
    pub hash: String,
    pub algorithm: String,
    pub success: bool,
    pub error_message: String,
}

/// Image processing result — sent to Dart
#[repr(C)]
#[derive(Debug, Clone)]
pub struct NativeImageResult {
    pub source_path: String,
    pub thumb_path: String,
    pub preview_path: String,
    pub thumb_size: u64,
    pub preview_size: u64,
    pub duration_ms: u64,
    pub success: bool,
    pub error_message: String,
}

// ── Shared state for pause/cancel ──

#[derive(Debug)]
struct OperationFlags {
    cancel: Arc<AtomicBool>,
    pause: Arc<AtomicBool>,
}

static CURRENT_OPERATION: std::sync::LazyLock<Mutex<Option<Arc<OperationFlags>>>> =
    std::sync::LazyLock::new(|| Mutex::new(None));

// ── Public API ──

/// Copy a single file using the best strategy
pub fn copy_single_file(
    source: String,
    destination: String,
    skip_existing: bool,
) -> NativeFileCopyResult {
    // Clone sebelum move ke closure agar bisa dipakai di unwrap_or_else
    let source_clone = source.clone();
    let destination_clone = destination.clone();
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        copy_single_file_inner(source, destination, skip_existing)
    }))
    .unwrap_or_else(|_| NativeFileCopyResult {
        source_path: source_clone,
        dest_path: destination_clone,
        bytes_copied: 0,
        duration_ms: 0,
        speed_mbps: 0.0,
        strategy_used: "Panic".to_string(),
        success: false,
        error_message: "Internal panic - operation failed".to_string(),
        skipped: false,
    })
}

fn copy_single_file_inner(
    source: String,
    destination: String,
    skip_existing: bool,
) -> NativeFileCopyResult {
    let src = match path_utils::canonicalize_path(Path::new(&source)) {
        Ok(path) => path,
        Err(e) => {
            return NativeFileCopyResult {
                source_path: source,
                dest_path: destination,
                bytes_copied: 0,
                duration_ms: 0,
                speed_mbps: 0.0,
                strategy_used: "Error".to_string(),
                success: false,
                error_message: e.to_string(),
                skipped: false,
            };
        }
    };
    let dst = match path_utils::canonicalize_path_allow_missing(Path::new(&destination)) {
        Ok(path) => path,
        Err(e) => {
            return NativeFileCopyResult {
                source_path: source,
                dest_path: destination,
                bytes_copied: 0,
                duration_ms: 0,
                speed_mbps: 0.0,
                strategy_used: "Error".to_string(),
                success: false,
                error_message: e.to_string(),
                skipped: false,
            };
        }
    };

    match file_copy::copy_file(&src, &dst, skip_existing) {
        Ok(r) => NativeFileCopyResult {
            source_path: r.source_path,
            dest_path: r.dest_path,
            bytes_copied: r.bytes_copied,
            duration_ms: r.duration_ms,
            speed_mbps: r.speed_mbps,
            strategy_used: r.strategy_used,
            success: r.success,
            error_message: r.error.unwrap_or_default(),
            skipped: r.skipped,
        },
        Err(e) => NativeFileCopyResult {
            source_path: source,
            dest_path: destination,
            bytes_copied: 0,
            duration_ms: 0,
            speed_mbps: 0.0,
            strategy_used: "Error".to_string(),
            success: false,
            error_message: e.to_string(),
            skipped: false,
        },
    }
}

/// Copy multiple files in parallel with progress reporting.
/// Returns batch result after all files are processed.
pub fn copy_files_batch(
    files: Vec<NativeFileEntry>,
    max_threads: u32,
    skip_existing: bool,
    verify_integrity: bool,
) -> NativeBatchResult {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        copy_files_batch_inner(files, max_threads, skip_existing, verify_integrity)
    }))
    .unwrap_or_else(|_| NativeBatchResult {
        results: Vec::new(),
        total_bytes_copied: 0,
        total_files: 0,
        successful_count: 0,
        failed_count: 0,
        skipped_count: 0,
        total_duration_ms: 0,
        average_speed_mbps: 0.0,
        peak_speed_mbps: 0.0,
        cancelled: false,
    })
}

fn copy_files_batch_inner(
    files: Vec<NativeFileEntry>,
    max_threads: u32,
    skip_existing: bool,
    verify_integrity: bool,
) -> NativeBatchResult {
    let op_flags = Arc::new(OperationFlags {
        cancel: Arc::new(AtomicBool::new(false)),
        pause: Arc::new(AtomicBool::new(false)),
    });

    {
        let mut current = CURRENT_OPERATION
            .lock()
            .expect("CURRENT_OPERATION mutex poisoned");
        if let Some(existing) = current.as_ref() {
            existing.cancel.store(true, Ordering::SeqCst);
        }
        *current = Some(Arc::clone(&op_flags));
    }

    let entries: Vec<parallel::FileEntry> = files
        .into_iter()
        .map(|f| parallel::FileEntry {
            source_path: f.source_path,
            dest_path: f.dest_path,
            size: f.size,
        })
        .collect();

    let result = parallel::copy_files_parallel(
        entries,
        max_threads as usize,
        skip_existing,
        verify_integrity,
        Arc::clone(&op_flags.cancel),
        Arc::clone(&op_flags.pause),
        None, // Progress via polling instead
    );

    NativeBatchResult {
        results: result
            .results
            .into_iter()
            .map(|r| NativeFileCopyResult {
                source_path: r.source_path,
                dest_path: r.dest_path,
                bytes_copied: r.bytes_copied,
                duration_ms: r.duration_ms,
                speed_mbps: r.speed_mbps,
                strategy_used: r.strategy_used,
                success: r.success,
                error_message: r.error.unwrap_or_default(),
                skipped: r.skipped,
            })
            .collect(),
        total_bytes_copied: result.total_bytes_copied,
        total_files: result.total_files,
        successful_count: result.successful_count,
        failed_count: result.failed_count,
        skipped_count: result.skipped_count,
        total_duration_ms: result.total_duration_ms,
        average_speed_mbps: result.average_speed_mbps,
        peak_speed_mbps: result.peak_speed_mbps,
        cancelled: result.cancelled,
    }
}

/// Pause the current copy operation
pub fn pause_copy() {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if let Some(current) = CURRENT_OPERATION
            .lock()
            .expect("CURRENT_OPERATION mutex poisoned")
            .as_ref()
        {
            current.pause.store(true, Ordering::SeqCst);
        }
    }));
}

/// Resume the current copy operation
pub fn resume_copy() {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if let Some(current) = CURRENT_OPERATION
            .lock()
            .expect("CURRENT_OPERATION mutex poisoned")
            .as_ref()
        {
            current.pause.store(false, Ordering::SeqCst);
        }
    }));
}

/// Cancel the current copy operation
pub fn cancel_copy() {
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if let Some(current) = CURRENT_OPERATION
            .lock()
            .expect("CURRENT_OPERATION mutex poisoned")
            .as_ref()
        {
            current.cancel.store(true, Ordering::SeqCst);
        }
    }));
}

/// Check if copy is currently paused
pub fn is_paused() -> bool {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        CURRENT_OPERATION
            .lock()
            .expect("CURRENT_OPERATION mutex poisoned")
            .as_ref()
            .map(|current| current.pause.load(Ordering::SeqCst))
            .unwrap_or(false)
    }))
    .unwrap_or(false)
}

/// Check if copy is cancelled
pub fn is_cancelled() -> bool {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        CURRENT_OPERATION
            .lock()
            .expect("CURRENT_OPERATION mutex poisoned")
            .as_ref()
            .map(|current| current.cancel.load(Ordering::SeqCst))
            .unwrap_or(false)
    }))
    .unwrap_or(false)
}

/// Compute file hash (MD5 or SHA256)
pub fn compute_file_hash(file_path: String, algorithm: String) -> NativeHashResult {
    // Clone sebelum move ke closure agar bisa dipakai di unwrap_or_else
    let algorithm_clone = algorithm.clone();
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        compute_file_hash_inner(file_path, algorithm)
    }))
    .unwrap_or_else(|_| NativeHashResult {
        hash: String::new(),
        algorithm: algorithm_clone,
        success: false,
        error_message: "Internal panic - hash failed".to_string(),
    })
}

fn compute_file_hash_inner(file_path: String, algorithm: String) -> NativeHashResult {
    let algo = match algorithm.to_lowercase().as_str() {
        "md5" => hash::HashAlgorithm::Md5,
        "sha256" => hash::HashAlgorithm::Sha256,
        _ => {
            return NativeHashResult {
                hash: String::new(),
                algorithm,
                success: false,
                error_message: "Unsupported algorithm".to_string(),
            }
        }
    };

    match hash::compute_hash(Path::new(&file_path), &algo) {
        Ok(h) => NativeHashResult {
            hash: h,
            algorithm,
            success: true,
            error_message: String::new(),
        },
        Err(e) => NativeHashResult {
            hash: String::new(),
            algorithm,
            success: false,
            error_message: e.to_string(),
        },
    }
}

/// Verify two files match by hash comparison
pub fn verify_file_integrity(source: String, destination: String, algorithm: String) -> bool {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        verify_file_integrity_inner(source, destination, algorithm)
    }))
    .unwrap_or(false)
}

fn verify_file_integrity_inner(source: String, destination: String, algorithm: String) -> bool {
    let algo = match algorithm.to_lowercase().as_str() {
        "md5" => hash::HashAlgorithm::Md5,
        "sha256" => hash::HashAlgorithm::Sha256,
        _ => return false,
    };

    hash::verify_files_match(Path::new(&source), Path::new(&destination), &algo).unwrap_or(false)
}

/// Scan directory and return list of files with their sizes
pub fn scan_directory(path: String, extensions: Vec<String>) -> Vec<NativeFileEntry> {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        scan_directory_inner(path, extensions)
    }))
    .unwrap_or_else(|_| Vec::new())
}

fn scan_directory_inner(path: String, extensions: Vec<String>) -> Vec<NativeFileEntry> {
    let dir = match path_utils::canonicalize_path(Path::new(&path)) {
        Ok(path) => path,
        Err(_) => return Vec::new(),
    };
    if !dir.is_dir() {
        return Vec::new();
    }

    // ✅ FIX #6: Ganti walkdir tanpa batas dengan batas keamanan eksplisit.
    // walkdir::WalkDir tanpa max_depth bisa hang di folder sistem / drive root.
    // Gunakan konstanta yang sama dengan Dart ScanLimits untuk konsistensi:
    // - max_depth = 10 level
    // - max_files = 50_000 file
    const MAX_DEPTH: usize = 10;
    const MAX_FILES: usize = 50_000;

    let normalized_ext: Vec<String> = extensions.iter().map(|e| e.to_lowercase()).collect();
    let mut results = Vec::new();

    let entries = walkdir::WalkDir::new(&dir)
        .follow_links(false)
        .max_depth(MAX_DEPTH)
        .into_iter()
        .filter_map(|e| e.ok()); // skip entry yang tidak bisa diakses (permission denied)

    for entry in entries {
        if results.len() >= MAX_FILES {
            break;
        }

        if !entry.file_type().is_file() {
            continue;
        }

        let file_path = entry.path();

        // Filter by extension if specified
        if !normalized_ext.is_empty() {
            match file_path.extension() {
                Some(ext) => {
                    let ext_str = ext.to_string_lossy().to_lowercase();
                    if !normalized_ext.iter().any(|e| e == &ext_str) {
                        continue;
                    }
                }
                None => continue,
            }
        }

        if let Ok(meta) = entry.metadata() {
            results.push(NativeFileEntry {
                source_path: file_path.to_string_lossy().to_string(),
                dest_path: String::new(),
                size: meta.len(),
            });
        }
    }

    results
}

/// Process images for web upload: generate thumbnail + preview WebP
pub fn process_images_for_upload(
    source_paths: Vec<String>,
    output_dir: String,
    thumb_width: u32,
    preview_width: u32,
    thumb_quality: u8,
    preview_quality: u8,
) -> Vec<NativeImageResult> {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        process_images_for_upload_inner(
            source_paths,
            output_dir,
            thumb_width,
            preview_width,
            thumb_quality,
            preview_quality,
        )
    }))
    .unwrap_or_else(|_| Vec::new())
}

fn process_images_for_upload_inner(
    source_paths: Vec<String>,
    output_dir: String,
    thumb_width: u32,
    preview_width: u32,
    thumb_quality: u8,
    preview_quality: u8,
) -> Vec<NativeImageResult> {
    let config = image_processing::ProcessConfig {
        thumb_width,
        preview_width,
        thumb_quality,
        preview_quality,
    };

    let paths: Vec<std::path::PathBuf> = source_paths
        .iter()
        .filter_map(|source| path_utils::canonicalize_path(Path::new(source)).ok())
        .collect();

    let out = match path_utils::canonicalize_path(Path::new(&output_dir)) {
        Ok(path) => path,
        Err(_) => {
            return Vec::new();
        }
    };

    // ✅ FIX #1: Pass cancel_flag dari CURRENT_OPERATION ke process_batch
    // agar user bisa menghentikan image processing dari Flutter.
    // Buat cancel_flag fresh jika tidak ada operasi aktif.
    let cancel_flag = CURRENT_OPERATION
        .lock()
        .ok()
        .and_then(|guard| guard.as_ref().map(|op| Arc::clone(&op.cancel)))
        .unwrap_or_else(|| Arc::new(AtomicBool::new(false)));

    let results = image_processing::process_batch(&paths, &out, &config, &cancel_flag);

    results
        .into_iter()
        .map(|r| NativeImageResult {
            source_path: r.source_path,
            thumb_path: r.thumb_path,
            preview_path: r.preview_path,
            thumb_size: r.thumb_size,
            preview_size: r.preview_size,
            duration_ms: r.duration_ms,
            success: r.success,
            error_message: r.error_message,
        })
        .collect()
}
