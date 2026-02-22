use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub fn canonicalize_path(path: &Path) -> io::Result<PathBuf> {
    path.canonicalize().map_err(|e| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("Invalid path {}: {}", path.display(), e),
        )
    })
}

pub fn canonicalize_path_allow_missing(path: &Path) -> io::Result<PathBuf> {
    if path.exists() {
        return canonicalize_path(path);
    }

    let parent = path.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("Invalid path {}", path.display()),
        )
    })?;

    let canonical_parent = fs::canonicalize(parent).map_err(|e| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("Invalid parent {}: {}", parent.display(), e),
        )
    })?;

    if let Some(file_name) = path.file_name() {
        Ok(canonical_parent.join(file_name))
    } else {
        Ok(canonical_parent)
    }
}
