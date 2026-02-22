//! File integrity verification via hashing (MD5, SHA256)

use md5::{Digest as Md5Digest, Md5};
use sha2::Sha256;
use std::fs::File;
use std::io::{self, BufReader, Read};
use std::path::Path;

const HASH_BUFFER_SIZE: usize = 1024 * 1024; // 1MB

#[derive(Debug, Clone)]
pub enum HashAlgorithm {
    Md5,
    Sha256,
}

/// Compute file hash using specified algorithm
pub fn compute_hash(path: &Path, algorithm: &HashAlgorithm) -> io::Result<String> {
    match algorithm {
        HashAlgorithm::Md5 => compute_md5(path),
        HashAlgorithm::Sha256 => compute_sha256(path),
    }
}

/// Verify two files are identical by comparing hashes
pub fn verify_files_match(src: &Path, dst: &Path, algorithm: &HashAlgorithm) -> io::Result<bool> {
    let src_hash = compute_hash(src, algorithm)?;
    let dst_hash = compute_hash(dst, algorithm)?;
    Ok(src_hash == dst_hash)
}

fn compute_md5(path: &Path) -> io::Result<String> {
    let file = File::open(path)?;
    let mut reader = BufReader::with_capacity(HASH_BUFFER_SIZE, file);
    let mut hasher = Md5::new();
    let mut buf = [0u8; HASH_BUFFER_SIZE];

    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}

fn compute_sha256(path: &Path) -> io::Result<String> {
    let file = File::open(path)?;
    let mut reader = BufReader::with_capacity(HASH_BUFFER_SIZE, file);
    let mut hasher = Sha256::new();
    let mut buf = [0u8; HASH_BUFFER_SIZE];

    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}
