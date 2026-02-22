//! Windows-specific high-performance file I/O
//!
//! Uses Win32 CopyFileExW for optimized copying.

use std::ffi::OsStr;
use std::fs;
use std::io;
use std::os::windows::ffi::OsStrExt;
use std::path::Path;
use windows::Win32::Foundation::PCWSTR;
use windows::Win32::Storage::FileSystem::CopyFileExW;

/// Copy file using Win32 API for optimized performance.
/// Falls back to std::fs::copy on error.
pub fn copy_file_win32(src: &Path, dst: &Path) -> io::Result<u64> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    let src_wide: Vec<u16> = OsStr::new(src)
        .encode_wide()
        .chain(Some(0))
        .collect();
    let dst_wide: Vec<u16> = OsStr::new(dst)
        .encode_wide()
        .chain(Some(0))
        .collect();

    unsafe {
        let success = CopyFileExW(
            PCWSTR(src_wide.as_ptr()),
            PCWSTR(dst_wide.as_ptr()),
            None,
            None,
            None,
            windows::Win32::Storage::FileSystem::COPY_FILE_FLAGS(0),
        );

        if !success.as_bool() {
            return Err(io::Error::last_os_error());
        }
    }

    fs::metadata(dst).map(|meta| meta.len())
}

/// Pre-allocate file on Windows
pub fn preallocate_file_win32(path: &Path, size: u64) -> io::Result<()> {
    let file = fs::File::create(path)?;
    file.set_len(size)?;
    Ok(())
}
