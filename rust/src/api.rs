//! Flutter Rust Bridge API
//!
//! Public API exposed to Dart via flutter_rust_bridge.
//! All functions here are callable from Flutter.

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::file_copy;
use crate::hash;
use crate::image_processing;
use crate::parallel;

// ── Data Transfer Objects (mirrored in Dart) ──

/// Single file copy result — sent to Dart
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
#[derive(Debug, Clone)]
pub struct NativeFileEntry {
    pub source_path: String,
    pub dest_path: String,
    pub size: u64,
}

/// Hash verification result
#[derive(Debug, Clone)]
pub struct NativeHashResult {
    pub hash: String,
    pub algorithm: String,
    pub success: bool,
    pub error_message: String,
}

/// Image processing result — sent to Dart
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

static CANCEL_FLAG: std::sync::LazyLock<Arc<AtomicBool>> =
    std::sync::LazyLock::new(|| Arc::new(AtomicBool::new(false)));
static PAUSE_FLAG: std::sync::LazyLock<Arc<AtomicBool>> =
    std::sync::LazyLock::new(|| Arc::new(AtomicBool::new(false)));

// ── Public API ──

/// Copy a single file using the best strategy
pub fn copy_single_file(
    source: String,
    destination: String,
    skip_existing: bool,
) -> NativeFileCopyResult {
    let src = Path::new(&source);
    let dst = Path::new(&destination);

    match file_copy::copy_file(src, dst, skip_existing) {
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
    // Reset flags
    CANCEL_FLAG.store(false, Ordering::Relaxed);
    PAUSE_FLAG.store(false, Ordering::Relaxed);

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
        Arc::clone(&CANCEL_FLAG),
        Arc::clone(&PAUSE_FLAG),
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
    PAUSE_FLAG.store(true, Ordering::Relaxed);
}

/// Resume the current copy operation
pub fn resume_copy() {
    PAUSE_FLAG.store(false, Ordering::Relaxed);
}

/// Cancel the current copy operation
pub fn cancel_copy() {
    CANCEL_FLAG.store(true, Ordering::Relaxed);
}

/// Check if copy is currently paused
pub fn is_paused() -> bool {
    PAUSE_FLAG.load(Ordering::Relaxed)
}

/// Check if copy is cancelled
pub fn is_cancelled() -> bool {
    CANCEL_FLAG.load(Ordering::Relaxed)
}

/// Compute file hash (MD5 or SHA256)
pub fn compute_file_hash(
    file_path: String,
    algorithm: String,
) -> NativeHashResult {
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
pub fn verify_file_integrity(
    source: String,
    destination: String,
    algorithm: String,
) -> bool {
    let algo = match algorithm.to_lowercase().as_str() {
        "md5" => hash::HashAlgorithm::Md5,
        "sha256" => hash::HashAlgorithm::Sha256,
        _ => return false,
    };

    hash::verify_files_match(
        Path::new(&source),
        Path::new(&destination),
        &algo,
    )
    .unwrap_or(false)
}

/// Scan directory and return list of files with their sizes
pub fn scan_directory(
    path: String,
    extensions: Vec<String>,
) -> Vec<NativeFileEntry> {
    let dir = Path::new(&path);
    if !dir.is_dir() {
        return Vec::new();
    }

    let mut results = Vec::new();

    let entries = walkdir::WalkDir::new(dir)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok());

    for entry in entries {
        if !entry.file_type().is_file() {
            continue;
        }

        let file_path = entry.path();

        // Filter by extension if specified
        if !extensions.is_empty() {
            if let Some(ext) = file_path.extension() {
                let ext_str = ext.to_string_lossy().to_lowercase();
                if !extensions
                    .iter()
                    .any(|e| e.to_lowercase() == ext_str)
                {
                    continue;
                }
            } else {
                continue;
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
    let config = image_processing::ProcessConfig {
        thumb_width,
        preview_width,
        thumb_quality,
        preview_quality,
    };

    let paths: Vec<std::path::PathBuf> = source_paths
        .iter()
        .map(std::path::PathBuf::from)
        .collect();

    let out = Path::new(&output_dir);
    let results = image_processing::process_batch(&paths, out, &config);

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
