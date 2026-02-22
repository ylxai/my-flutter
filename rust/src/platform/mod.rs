//! Platform-specific file I/O optimizations

#[cfg(target_os = "linux")]
pub mod linux;

#[cfg(target_os = "windows")]
pub mod windows;

use std::fs;
use std::io;
use std::path::Path;

/// Copy a single file using platform-optimized method.
/// Falls back to standard copy if platform-specific fails.
pub fn copy_file_optimized(src: &Path, dst: &Path) -> io::Result<u64> {
    // Ensure destination directory exists
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    #[cfg(target_os = "linux")]
    {
        if let Ok(bytes) = linux::copy_file_range_copy(src, dst) {
            return Ok(bytes);
        }
    }

    #[cfg(target_os = "windows")]
    {
        match windows::copy_file_win32(src, dst) {
            Ok(bytes) => return Ok(bytes),
            Err(_) => {} // fallback below
        }
    }

    // Fallback: standard copy
    fs::copy(src, dst)
}

/// Pre-allocate file to reduce fragmentation
pub fn preallocate_file(path: &Path, size: u64) -> io::Result<()> {
    #[cfg(target_os = "linux")]
    {
        return linux::fallocate_file(path, size);
    }

    #[cfg(target_os = "windows")]
    {
        return windows::preallocate_file_win32(path, size);
    }

    #[allow(unreachable_code)]
    {
        // Fallback: create empty file
        let file = fs::File::create(path)?;
        file.set_len(size)?;
        Ok(())
    }
}
