//! Parallel file copy manager
//!
//! Uses rayon for data parallelism and crossbeam for progress channels.

use crossbeam_channel::Sender;
use rayon::prelude::*;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Once};
use std::time::Instant;

use crate::file_copy::{self, FileCopyResult};
use crate::hash::{self, HashAlgorithm};

/// Progress update sent during copy operations
#[derive(Debug, Clone)]
pub struct CopyProgress {
    pub total_files: u32,
    pub processed_files: u32,
    pub current_file: String,
    pub bytes_copied: u64,
    pub total_bytes: u64,
    pub speed_mbps: f64,
    pub skipped_count: u32,
    pub failed_count: u32,
}

/// Batch copy result
#[derive(Debug, Clone)]
pub struct BatchCopyResult {
    pub results: Vec<FileCopyResult>,
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

/// File entry for batch operations
#[derive(Debug, Clone)]
pub struct FileEntry {
    pub source_path: String,
    pub dest_path: String,
    pub size: u64,
}

static GLOBAL_POOL_INIT: Once = Once::new();

fn configure_global_pool(max_threads: usize) {
    GLOBAL_POOL_INIT.call_once(|| {
        let _ = rayon::ThreadPoolBuilder::new()
            .num_threads(max_threads.max(1))
            .build_global();
    });
}

/// Copy files in parallel with progress reporting
pub fn copy_files_parallel(
    files: Vec<FileEntry>,
    max_threads: usize,
    skip_existing: bool,
    verify_hash: bool,
    cancel_flag: Arc<AtomicBool>,
    pause_flag: Arc<AtomicBool>,
    progress_tx: Option<Sender<CopyProgress>>,
) -> BatchCopyResult {
    let start = Instant::now();
    let total_files = files.len() as u32;
    let total_bytes: u64 = files.iter().map(|f| f.size).sum();

    let processed = Arc::new(AtomicU64::new(0));
    let bytes_copied = Arc::new(AtomicU64::new(0));
    let skipped = Arc::new(AtomicU64::new(0));
    let failed = Arc::new(AtomicU64::new(0));

    configure_global_pool(max_threads);

    let results: Vec<FileCopyResult> = files
        .par_iter()
        .map(|entry| {
            // Check cancellation
            if cancel_flag.load(Ordering::Relaxed) {
                return FileCopyResult {
                    source_path: entry.source_path.clone(),
                    dest_path: entry.dest_path.clone(),
                    bytes_copied: 0,
                    duration_ms: 0,
                    speed_mbps: 0.0,
                    strategy_used: "Cancelled".to_string(),
                    success: false,
                    error: Some("Cancelled by user".to_string()),
                    skipped: false,
                };
            }

            // Wait while paused
            while pause_flag.load(Ordering::Relaxed) {
                if cancel_flag.load(Ordering::Relaxed) {
                    break;
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }

            let src = Path::new(&entry.source_path);
            let dst = Path::new(&entry.dest_path);

            let mut file_result = match file_copy::copy_file(src, dst, skip_existing) {
                Ok(r) => r,
                Err(e) => FileCopyResult {
                    source_path: entry.source_path.clone(),
                    dest_path: entry.dest_path.clone(),
                    bytes_copied: 0,
                    duration_ms: 0,
                    speed_mbps: 0.0,
                    strategy_used: "Error".to_string(),
                    success: false,
                    error: Some(e.to_string()),
                    skipped: false,
                },
            };

            if verify_hash && file_result.success && !file_result.skipped {
                match hash::verify_files_match(src, dst, &HashAlgorithm::Sha256) {
                    Ok(true) => {}
                    Ok(false) => {
                        file_result.success = false;
                        file_result.error = Some("Hash mismatch".to_string());
                    }
                    Err(e) => {
                        file_result.success = false;
                        file_result.error = Some(format!("Verify failed: {}", e));
                    }
                }
            }

            if file_result.skipped {
                skipped.fetch_add(1, Ordering::Relaxed);
            } else if file_result.success {
                bytes_copied.fetch_add(file_result.bytes_copied, Ordering::Relaxed);
            } else {
                failed.fetch_add(1, Ordering::Relaxed);
            }

            let idx = processed.fetch_add(1, Ordering::Relaxed) + 1;

            // Send progress update
            if let Some(ref tx) = progress_tx {
                let elapsed = start.elapsed().as_secs_f64();
                let copied = bytes_copied.load(Ordering::Relaxed);
                let speed = if elapsed > 0.0 {
                    (copied as f64 / 1024.0 / 1024.0) / elapsed
                } else {
                    0.0
                };

                let _ = tx.try_send(CopyProgress {
                    total_files,
                    processed_files: idx as u32,
                    current_file: entry
                        .source_path
                        .rsplit(['/', '\\'])
                        .next()
                        .unwrap_or("")
                        .to_string(),
                    bytes_copied: copied,
                    total_bytes,
                    speed_mbps: speed,
                    skipped_count: skipped.load(Ordering::Relaxed) as u32,
                    failed_count: failed.load(Ordering::Relaxed) as u32,
                });
            }

            file_result
        })
        .collect();

    let duration = start.elapsed();
    let total_copied = bytes_copied.load(Ordering::Relaxed);
    let avg_speed = if duration.as_secs_f64() > 0.0 {
        (total_copied as f64 / 1024.0 / 1024.0) / duration.as_secs_f64()
    } else {
        0.0
    };

    let peak = results.iter().map(|r| r.speed_mbps).fold(0.0f64, f64::max);

    let success_count = results.iter().filter(|r| r.success && !r.skipped).count();

    BatchCopyResult {
        results,
        total_bytes_copied: total_copied,
        total_files,
        successful_count: success_count as u32,
        failed_count: failed.load(Ordering::Relaxed) as u32,
        skipped_count: skipped.load(Ordering::Relaxed) as u32,
        total_duration_ms: duration.as_millis() as u64,
        average_speed_mbps: avg_speed,
        peak_speed_mbps: peak,
        cancelled: cancel_flag.load(Ordering::Relaxed),
    }
}
