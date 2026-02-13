//! Image processing module
//!
//! Decodes JPEG images, resizes them, and encodes to WebP format.
//! Used for generating thumbnails and previews for web gallery upload.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use image::codecs::webp::WebPEncoder;
use image::imageops::FilterType;
use image::DynamicImage;
use image::ImageReader;

/// Result of processing a single image
#[derive(Debug, Clone)]
pub struct ImageProcessResult {
    pub source_path: String,
    pub thumb_path: String,
    pub preview_path: String,
    pub thumb_size: u64,
    pub preview_size: u64,
    pub duration_ms: u64,
    pub success: bool,
    pub error_message: String,
}

/// Configuration for image processing
#[derive(Debug, Clone)]
pub struct ProcessConfig {
    pub thumb_width: u32,
    pub preview_width: u32,
    pub thumb_quality: u8,
    pub preview_quality: u8,
}

impl Default for ProcessConfig {
    fn default() -> Self {
        Self {
            thumb_width: 400,
            preview_width: 1920,
            thumb_quality: 80,
            preview_quality: 85,
        }
    }
}

/// Process a single image: generate thumbnail + preview in WebP
pub fn process_image(
    source_path: &Path,
    output_dir: &Path,
    config: &ProcessConfig,
) -> ImageProcessResult {
    let start = Instant::now();
    let source_str = source_path.to_string_lossy().to_string();

    let stem = source_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    let thumb_path = output_dir.join(format!("{}_thumb.webp", stem));
    let preview_path = output_dir.join(format!("{}_preview.webp", stem));

    // Decode source image
    let img = match ImageReader::open(source_path) {
        Ok(reader) => match reader.with_guessed_format() {
            Ok(r) => match r.decode() {
                Ok(img) => img,
                Err(e) => {
                    return make_error(
                        &source_str, start,
                        &format!("Decode failed: {}", e),
                    );
                }
            },
            Err(e) => {
                return make_error(
                    &source_str, start,
                    &format!("Format guess failed: {}", e),
                );
            }
        },
        Err(e) => {
            return make_error(
                &source_str, start,
                &format!("Open failed: {}", e),
            );
        }
    };

    // Generate thumbnail
    if let Err(e) = resize_and_save_webp(
        &img, config.thumb_width, &thumb_path,
    ) {
        return make_error(
            &source_str, start,
            &format!("Thumbnail failed: {}", e),
        );
    }

    // Generate preview
    if let Err(e) = resize_and_save_webp(
        &img, config.preview_width, &preview_path,
    ) {
        return make_error(
            &source_str, start,
            &format!("Preview failed: {}", e),
        );
    }

    let thumb_size = fs::metadata(&thumb_path)
        .map(|m| m.len())
        .unwrap_or(0);
    let preview_size = fs::metadata(&preview_path)
        .map(|m| m.len())
        .unwrap_or(0);

    ImageProcessResult {
        source_path: source_str,
        thumb_path: thumb_path.to_string_lossy().to_string(),
        preview_path: preview_path.to_string_lossy().to_string(),
        thumb_size,
        preview_size,
        duration_ms: start.elapsed().as_millis() as u64,
        success: true,
        error_message: String::new(),
    }
}

/// Process multiple images using rayon for parallelism
pub fn process_batch(
    source_paths: &[PathBuf],
    output_dir: &Path,
    config: &ProcessConfig,
) -> Vec<ImageProcessResult> {
    use rayon::prelude::*;

    // Ensure output subdirectories exist
    let thumbs_dir = output_dir.join("thumbs");
    let previews_dir = output_dir.join("previews");
    let _ = fs::create_dir_all(&thumbs_dir);
    let _ = fs::create_dir_all(&previews_dir);

    source_paths
        .par_iter()
        .map(|src| {
            let stem = src
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "unknown".to_string());

            let start = Instant::now();
            let source_str = src.to_string_lossy().to_string();

            // Decode
            let img = match ImageReader::open(src) {
                Ok(r) => match r.with_guessed_format() {
                    Ok(r2) => match r2.decode() {
                        Ok(img) => img,
                        Err(e) => {
                            return make_error(
                                &source_str, start,
                                &format!("Decode: {}", e),
                            );
                        }
                    },
                    Err(e) => {
                        return make_error(
                            &source_str, start,
                            &format!("Format: {}", e),
                        );
                    }
                },
                Err(e) => {
                    return make_error(
                        &source_str, start,
                        &format!("Open: {}", e),
                    );
                }
            };

            let thumb_path = thumbs_dir
                .join(format!("{}.webp", stem));
            let preview_path = previews_dir
                .join(format!("{}.webp", stem));

            // Thumbnail
            if let Err(e) = resize_and_save_webp(
                &img, config.thumb_width, &thumb_path,
            ) {
                return make_error(
                    &source_str, start,
                    &format!("Thumb: {}", e),
                );
            }

            // Preview
            if let Err(e) = resize_and_save_webp(
                &img, config.preview_width, &preview_path,
            ) {
                return make_error(
                    &source_str, start,
                    &format!("Preview: {}", e),
                );
            }

            let thumb_size = fs::metadata(&thumb_path)
                .map(|m| m.len())
                .unwrap_or(0);
            let preview_size = fs::metadata(&preview_path)
                .map(|m| m.len())
                .unwrap_or(0);

            ImageProcessResult {
                source_path: source_str,
                thumb_path: thumb_path
                    .to_string_lossy().to_string(),
                preview_path: preview_path
                    .to_string_lossy().to_string(),
                thumb_size,
                preview_size,
                duration_ms: start.elapsed().as_millis() as u64,
                success: true,
                error_message: String::new(),
            }
        })
        .collect()
}

// ── Helpers ──

/// Resize image and save as lossless WebP
fn resize_and_save_webp(
    img: &DynamicImage,
    max_width: u32,
    output: &Path,
) -> anyhow::Result<()> {
    // Only resize if image is wider than target
    let resized = if img.width() > max_width {
        let ratio = max_width as f64 / img.width() as f64;
        let new_height = (img.height() as f64 * ratio) as u32;
        img.resize_exact(max_width, new_height, FilterType::Lanczos3)
    } else {
        img.clone()
    };

    // Save as WebP using the image crate's built-in encoder
    let rgba = resized.to_rgba8();
    let file = fs::File::create(output)?;
    let encoder = WebPEncoder::new_lossless(file);
    encoder.encode(
        rgba.as_raw(),
        rgba.width(),
        rgba.height(),
        image::ExtendedColorType::Rgba8,
    )?;

    Ok(())
}

fn make_error(
    source: &str,
    start: Instant,
    msg: &str,
) -> ImageProcessResult {
    ImageProcessResult {
        source_path: source.to_string(),
        thumb_path: String::new(),
        preview_path: String::new(),
        thumb_size: 0,
        preview_size: 0,
        duration_ms: start.elapsed().as_millis() as u64,
        success: false,
        error_message: msg.to_string(),
    }
}
