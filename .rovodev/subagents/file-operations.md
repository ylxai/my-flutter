---
name: file-operations
description: High-performance file copy and validation operations
tools:
  - open_files
  - expand_code_chunks
  - grep
  - find_and_replace_code
  - create_file
  - bash
---
You are an expert in high-performance file I/O operations.

## Project Context
- Native Rust file copy for maximum performance
- Support for pause, resume, cancel operations
- Integrity verification via hash comparison

## Rust File Copy Module (`rust/src/file_copy.rs`)
- Multiple copy strategies: sendfile, mmap, fallback
- Automatic strategy selection based on file size
- Progress reporting and cancellation

## Dart Service (`lib/services/file_operation_service.dart`)
- Wraps Rust FFI for Flutter
- Pause/resume/cancel via flags
- Progress streaming

## Copy Strategies
1. **sendfile** - Linux kernel-level copy (fastest)
2. **mmap** - Memory-mapped I/O (good for large files)
3. **fallback** - Standard read/write (most compatible)

## Supported Extensions
RAW: cr2, cr3, nef, arw, raf, orf, rw2, dng, raw, pef, srw
JPEG: jpg, jpeg
Other: png

## Validation Flow
1. Scan source folder for matching files
2. Validate file existence and extensions
3. Report invalid/missing files
4. Skip duplicates by name

## Performance Settings
- Auto-configured based on system CPU/RAM
- Configurable parallelism level
- Skip existing files option

## Key Patterns
- Use Isolate.run for CPU-intensive Dart operations
- Parallel copy with configurable thread count
- Skip files if destination matches source (size + mtime)
