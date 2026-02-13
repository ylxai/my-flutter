//! Linux-specific high-performance file I/O
//!
//! Uses copy_file_range() for kernel-space zero-copy,
//! and fallocate() for pre-allocation.

use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::Path;

use nix::libc;

/// Copy file using copy_file_range() syscall (kernel-space, zero-copy).
/// Available on Linux 4.5+. Much faster than userspace copy.
pub fn copy_file_range_copy(src: &Path, dst: &Path) -> io::Result<u64> {
    let src_file = File::open(src)?;
    let src_meta = src_file.metadata()?;
    let file_size = src_meta.len();

    // Ensure destination directory exists
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent)?;
    }

    let dst_file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(dst)?;

    // Pre-allocate destination file
    dst_file.set_len(file_size)?;

    let src_fd = src_file.as_raw_fd();
    let dst_fd = dst_file.as_raw_fd();

    let mut total_copied: u64 = 0;
    let chunk_size: usize = 128 * 1024 * 1024; // 128MB chunks

    while total_copied < file_size {
        let remaining = file_size - total_copied;
        let to_copy = std::cmp::min(remaining as usize, chunk_size);

        let mut off_in = total_copied as i64;
        let mut off_out = total_copied as i64;

        let copied = unsafe {
            libc::copy_file_range(
                src_fd,
                &mut off_in,
                dst_fd,
                &mut off_out,
                to_copy,
                0,
            )
        };

        if copied < 0 {
            return Err(io::Error::last_os_error());
        }
        if copied == 0 {
            break;
        }

        total_copied += copied as u64;
    }

    Ok(total_copied)
}

/// Pre-allocate file using fallocate() to reduce fragmentation
pub fn fallocate_file(path: &Path, size: u64) -> io::Result<()> {
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(path)?;

    let fd = file.as_raw_fd();
    let ret = unsafe { libc::fallocate(fd, 0, 0, size as i64) };

    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(())
}

extern "C" {
    fn copy_file_range(
        fd_in: libc::c_int,
        off_in: *mut libc::off_t,
        fd_out: libc::c_int,
        off_out: *mut libc::off_t,
        len: libc::size_t,
        flags: libc::c_uint,
    ) -> libc::ssize_t;
}
