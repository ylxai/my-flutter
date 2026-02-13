//! High-Performance File Copy Engine
//!
//! Supports multiple copy strategies based on file size:
//! - Small files (<10MB): buffered copy
//! - Medium files (10MB-1GB): memory-mapped copy
//! - Large files (>1GB): chunked memory-mapped copy

use memmap2::MmapOptions;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write, BufReader, BufWriter};
use std::path::Path;

use crate::platform;

const SMALL_FILE_THRESHOLD: u64 = 10 * 1024 * 1024; // 10MB
const LARGE_FILE_THRESHOLD: u64 = 1024 * 1024 * 1024; // 1GB
const BUFFER_SIZE: usize = 1024 * 1024; // 1MB buffer
const MMAP_CHUNK_SIZE: usize = 256 * 1024 * 1024; // 256MB chunks

/// Strategy selection result
#[derive(Debug, Clone)]
pub enum CopyStrategy {
    Buffered,
    MemoryMapped,
    ChunkedMemoryMapped,
    PlatformOptimized,
}

/// Result of a single file copy operation
#[derive(Debug, Clone)]
pub struct FileCopyResult {
    pub source_path: String,
    pub dest_path: String,
    pub bytes_copied: u64,
    pub duration_ms: u64,
    pub speed_mbps: f64,
    pub strategy_used: String,
    pub success: bool,
    pub error: Option<String>,
    pub skipped: bool,
}

/// Select the best copy strategy based on file size
pub fn select_strategy(file_size: u64) -> CopyStrategy {
    if file_size < SMALL_FILE_THRESHOLD {
        CopyStrategy::PlatformOptimized
    } else if file_size < LARGE_FILE_THRESHOLD {
        CopyStrategy::MemoryMapped
    } else {
        CopyStrategy::ChunkedMemoryMapped
    }
}

/// Copy a single file using the best strategy
pub fn copy_file(
    src: &Path,
    dst: &Path,
    skip_existing: bool,
) -> io::Result<FileCopyResult> {
    let start = std::time::Instant::now();
    let src_str = src.to_string_lossy().to_string();
    let dst_str = dst.to_string_lossy().to_string();

    // Smart copy: skip if file exists with same size
    if skip_existing && dst.exists() {
        let src_meta = fs::metadata(src)?;
        let dst_meta = fs::metadata(dst)?;
        if src_meta.len() == dst_meta.len() {
            return Ok(FileCopyResult {
                source_path: src_str,
                dest_path: dst_str,
                bytes_copied: 0,
                duration_ms: 0,
                speed_mbps: 0.0,
                strategy_used: "Skipped".to_string(),
                success: true,
                error: None,
                skipped: true,
            });
        }
    }

    let src_meta = fs::metadata(src)?;
    let file_size = src_meta.len();
    let strategy = select_strategy(file_size);

    let result = match strategy {
        CopyStrategy::PlatformOptimized => {
            platform::copy_file_optimized(src, dst)
        }
        CopyStrategy::Buffered => {
            copy_buffered(src, dst)
        }
        CopyStrategy::MemoryMapped => {
            copy_memory_mapped(src, dst).or_else(|_| copy_buffered(src, dst))
        }
        CopyStrategy::ChunkedMemoryMapped => {
            copy_chunked_mmap(src, dst).or_else(|_| copy_buffered(src, dst))
        }
    };

    let duration = start.elapsed();
    let duration_ms = duration.as_millis() as u64;

    match result {
        Ok(bytes) => {
            let speed = if duration.as_secs_f64() > 0.0 {
                (bytes as f64 / 1024.0 / 1024.0) / duration.as_secs_f64()
            } else {
                0.0
            };

            Ok(FileCopyResult {
                source_path: src_str,
                dest_path: dst_str,
                bytes_copied: bytes,
                duration_ms,
                speed_mbps: speed,
                strategy_used: format!("{:?}", select_strategy(file_size)),
                success: true,
                error: None,
                skipped: false,
            })
        }
        Err(e) => Ok(FileCopyResult {
            source_path: src_str,
            dest_path: dst_str,
            bytes_copied: 0,
            duration_ms,
            speed_mbps: 0.0,
            strategy_used: format!("{:?}", select_strategy(file_size)),
            success: false,
            error: Some(e.to_string()),
            skipped: false,
        }),
    }
}

/// Buffered copy for small files
fn copy_buffered(src: &Path, dst: &Path) -> io::Result<u64> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    let src_file = File::open(src)?;
    let dst_file = File::create(dst)?;

    let mut reader = BufReader::with_capacity(BUFFER_SIZE, src_file);
    let mut writer = BufWriter::with_capacity(BUFFER_SIZE, dst_file);

    let mut total: u64 = 0;
    let mut buf = vec![0u8; BUFFER_SIZE];

    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        writer.write_all(&buf[..n])?;
        total += n as u64;
    }
    writer.flush()?;
    Ok(total)
}

/// Memory-mapped copy for medium files
fn copy_memory_mapped(src: &Path, dst: &Path) -> io::Result<u64> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    let src_file = File::open(src)?;
    let src_meta = src_file.metadata()?;
    let file_size = src_meta.len();

    if file_size == 0 {
        File::create(dst)?;
        return Ok(0);
    }

    let mmap = unsafe { MmapOptions::new().map(&src_file)? };

    let dst_file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(dst)?;

    dst_file.set_len(file_size)?;

    let mut dst_mmap = unsafe { memmap2::MmapMut::map_mut(&dst_file)? };
    dst_mmap.copy_from_slice(&mmap);
    dst_mmap.flush()?;

    Ok(file_size)
}

/// Chunked memory-mapped copy for large files (>1GB)
fn copy_chunked_mmap(src: &Path, dst: &Path) -> io::Result<u64> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    let src_file = File::open(src)?;
    let src_meta = src_file.metadata()?;
    let file_size = src_meta.len();

    if file_size == 0 {
        File::create(dst)?;
        return Ok(0);
    }

    // Pre-allocate destination
    platform::preallocate_file(dst, file_size)?;

    let dst_file = OpenOptions::new().write(true).open(dst)?;

    let mut offset: u64 = 0;
    while offset < file_size {
        let remaining = file_size - offset;
        let chunk_len = std::cmp::min(remaining as usize, MMAP_CHUNK_SIZE);

        let src_mmap = unsafe {
            MmapOptions::new()
                .offset(offset)
                .len(chunk_len)
                .map(&src_file)?
        };

        let mut dst_mmap = unsafe {
            MmapOptions::new()
                .offset(offset)
                .len(chunk_len)
                .map_mut(&dst_file)?
        };

        dst_mmap.copy_from_slice(&src_mmap);
        dst_mmap.flush()?;

        offset += chunk_len as u64;
    }

    Ok(file_size)
}
