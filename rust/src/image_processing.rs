//! Image processing module
//!
//! Decodes JPEG images, resizes them, and encodes to WebP format.
//! Used for generating thumbnails and previews for web gallery upload.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

use image::imageops::FilterType;
use image::DynamicImage;
use image::ImageReader;
use webp::Encoder;

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

/// Decode sebuah gambar dari path — logika terpusat agar tidak duplikat
/// antara [process_image] dan [process_batch].
///
/// `start` diambil sebagai reference agar tidak di-move ke dalam fungsi ini,
/// sehingga caller masih bisa menggunakan `start.elapsed()` setelah decode.
fn decode_image(
    source_path: &Path,
    source_str: &str,
    start: &Instant,
) -> Result<DynamicImage, ImageProcessResult> {
    let reader = ImageReader::open(source_path)
        .map_err(|e| make_error(source_str, start, &format!("Open failed: {}", e)))?;
    let reader = reader
        .with_guessed_format()
        .map_err(|e| make_error(source_str, start, &format!("Format guess failed: {}", e)))?;
    reader
        .decode()
        .map_err(|e| make_error(source_str, start, &format!("Decode failed: {}", e)))
}

/// Process a single image: generate thumbnail + preview in WebP.
///
/// Output path:
/// - thumbnail → `{output_dir}/{stem}_thumb.webp`
/// - preview   → `{output_dir}/{stem}_preview.webp`
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

    // ✅ FIX P2: Gunakan decode_image() — tidak duplikat logika decode
    // Pass &start agar start tidak di-move, masih bisa dipakai di bawah
    let img = match decode_image(source_path, &source_str, &start) {
        Ok(img) => img,
        Err(result) => return result,
    };

    if let Err(e) =
        resize_and_save_webp(&img, config.thumb_width, config.thumb_quality, &thumb_path)
    {
        return make_error(&source_str, &start, &format!("Thumbnail failed: {}", e));
    }

    if let Err(e) = resize_and_save_webp(
        &img,
        config.preview_width,
        config.preview_quality,
        &preview_path,
    ) {
        return make_error(&source_str, &start, &format!("Preview failed: {}", e));
    }

    let thumb_size = fs::metadata(&thumb_path).map(|m| m.len()).unwrap_or(0);
    let preview_size = fs::metadata(&preview_path).map(|m| m.len()).unwrap_or(0);

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

/// Process multiple images secara paralel menggunakan rayon.
///
/// ✅ FIX P2: Menggunakan [decode_image] yang terpusat — tidak ada duplikasi
/// logika decode antara process_image dan process_batch.
///
/// ✅ FIX #5: Batasi concurrency rayon untuk mencegah OOM.
/// Tanpa batas, rayon akan memproses SEMUA gambar secara paralel sekaligus —
/// 100 foto RAW @30MB = 3GB RAM hanya untuk decode. Solusi: gunakan thread
/// pool lokal dengan jumlah thread = min(CPU/2, 4) agar:
/// - Maksimum ~4 gambar di-decode bersamaan
/// - Sisanya antri dan menunggu slot bebas
/// - Total RAM usage terkontrol
///
/// Output path per file:
/// - thumbnail → `{output_dir}/thumbs/{stem}.webp`
/// - preview   → `{output_dir}/previews/{stem}.webp`
pub fn process_batch(
    source_paths: &[PathBuf],
    output_dir: &Path,
    config: &ProcessConfig,
) -> Vec<ImageProcessResult> {
    use rayon::prelude::*;

    // Pastikan subdirektori output sudah ada sebelum parallel processing
    let thumbs_dir = output_dir.join("thumbs");
    let previews_dir = output_dir.join("previews");
    let _ = fs::create_dir_all(&thumbs_dir);
    let _ = fs::create_dir_all(&previews_dir);

    // ✅ FIX #5: Buat thread pool lokal dengan concurrency terbatas.
    // num_cpus / 2 memberi ruang untuk IO dan main thread.
    // Clamp ke 1..=4 agar tidak OOM di mesin RAM kecil maupun mesin besar.
    let num_threads = (num_cpus::get() / 2).clamp(1, 4);
    let pool = rayon::ThreadPoolBuilder::new()
        .num_threads(num_threads)
        .build()
        .unwrap_or_else(|_| {
            // Fallback: gunakan global pool jika build gagal
            rayon::ThreadPoolBuilder::new()
                .num_threads(2)
                .build()
                .expect("Fallback thread pool build failed")
        });

    pool.install(|| {
        source_paths.par_iter().map(|src| {
            let start = Instant::now();
            let source_str = src.to_string_lossy().to_string();

            let stem = src
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "unknown".to_string());

            // ✅ Gunakan decode_image() terpusat — tidak duplikasi logika
            // Pass &start agar start tidak di-move, masih bisa dipakai di bawah
            let img = match decode_image(src, &source_str, &start) {
                Ok(img) => img,
                Err(result) => return result,
            };

            let thumb_path = thumbs_dir.join(format!("{}.webp", stem));
            let preview_path = previews_dir.join(format!("{}.webp", stem));

            if let Err(e) =
                resize_and_save_webp(&img, config.thumb_width, config.thumb_quality, &thumb_path)
            {
                return make_error(&source_str, &start, &format!("Thumb: {}", e));
            }

            if let Err(e) = resize_and_save_webp(
                &img,
                config.preview_width,
                config.preview_quality,
                &preview_path,
            ) {
                return make_error(&source_str, &start, &format!("Preview: {}", e));
            }

            let thumb_size = fs::metadata(&thumb_path).map(|m| m.len()).unwrap_or(0);
            let preview_size = fs::metadata(&preview_path).map(|m| m.len()).unwrap_or(0);

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
        })
        .collect()
    })
}

// ── Helpers ──

/// Resize image and save as lossless WebP
fn resize_and_save_webp(
    img: &DynamicImage,
    max_width: u32,
    quality: u8,
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
    let q = quality.clamp(1, 100) as f32;
    let encoder = Encoder::from_rgba(rgba.as_raw(), rgba.width(), rgba.height());
    let webp = encoder.encode(q);
    fs::write(output, &*webp)?;

    Ok(())
}

fn make_error(source: &str, start: &Instant, msg: &str) -> ImageProcessResult {
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
