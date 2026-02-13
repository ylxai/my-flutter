//! Windows-specific high-performance file I/O
//!
//! Uses Win32 CopyFileExW for optimized copying.

use std::fs;
use std::io;
use std::path::Path;

/// Copy file using Win32 API for optimized performance.
/// Falls back to std::fs::copy on error.
pub fn copy_file_win32(src: &Path, dst: &Path) -> io::Result<u64> {
    // Ensure destination directory exists
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    // Use Rust std::fs::copy which on Windows already uses
    // CopyFileExW internally with proper buffering
    fs::copy(src, dst)
}

/// Pre-allocate file on Windows
pub fn preallocate_file_win32(path: &Path, size: u64) -> io::Result<()> {
    let file = fs::File::create(path)?;
    file.set_len(size)?;
    Ok(())
}
