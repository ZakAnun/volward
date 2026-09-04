use std::path::Path;

use crate::capability::{
    group_items_by_direct_child, paginate_items, AnalysisConfidence, AnalysisItem,
    AnalysisOptions, AnalysisPreview, AnalysisSummary, Capability, CapabilityAnalysisResult,
    CapabilityLevel, DeletionPlan, Recommendation, SimilarityPreset,
};
use crate::capability_registry::{
    CapabilityAnalysisError, CapabilityAnalyzer, CapabilityProgressSink,
};
use crate::index::{path_is_at_or_below, SnapshotIndex};
use crate::{CapabilityAnalysisPhase, CAPABILITY_SCHEMA_VERSION};

pub const SIMILAR_PHOTOS_ANALYZER_VERSION: &str = "similar_photos-v1";
const PHOTO_PRESET_VERSION: u32 = 1;

/// Upper bound on decoded pixels (24 MP ≈ 72 MB RGB) so decode memory stays
/// bounded; larger images are surfaced as review-only rather than decoded.
const MAX_DECODE_PIXELS: u64 = 24_000_000;
const IMAGE_EXTENSIONS: [&str; 8] = [
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff",
];
/// 8x8 grayscale average hash.
const AHASH_SIZE: u32 = 8;
/// 4 bins per RGB channel → 64-dim normalized color histogram.
const HIST_BINS: usize = 4;
const HIST_DIM: usize = HIST_BINS * HIST_BINS * HIST_BINS;

/// Perceptual signature for one image. Image bytes never leave this
/// function — only this signature is retained.
#[derive(Clone)]
struct PhotoSignature {
    path: String,
    size_bytes: u64,
    width: u32,
    height: u32,
    modified_at_ms: Option<i64>,
    ahash: u64,
    histogram: [u32; HIST_DIM],
}

enum PhotoRead {
    Signature(Box<PhotoSignature>),
    /// Decode failure / unsupported / oversized — review-only, never a target.
    ReviewOnly { path: String, size_bytes: u64, modified_at_ms: Option<i64>, reason: String },
}

/// Similar-photo analysis: decode → downscale → average hash + color
/// histogram; group by preset thresholds (strict/balanced/loose, versioned).
/// Decode failures become review-only items; nothing is uploaded.
pub struct SimilarPhotoAnalyzer {
    protected_prefixes: Vec<String>,
}

impl SimilarPhotoAnalyzer {
    pub fn new(protected_prefixes: Vec<String>) -> Self {
        Self { protected_prefixes }
    }

    fn is_protected(&self, path: &str) -> bool {
        self.protected_prefixes
            .iter()
            .any(|prefix| path_is_at_or_below(path, prefix))
    }
}

impl CapabilityAnalyzer for SimilarPhotoAnalyzer {
    fn capability(&self) -> Capability {
        Capability::SimilarPhotos
    }

    fn analyze(
        &self,
        index: &SnapshotIndex,
        normalized_root: &str,
        options: &AnalysisOptions,
        progress: &dyn CapabilityProgressSink,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
        let preset = options.similarity_preset;
        let page_size = options.page_size as usize;
        let mut photos: Vec<PhotoSignature> = Vec::new();
        let mut review_only: Vec<AnalysisItem> = Vec::new();
        let mut blocked_targets = Vec::new();
        let mut file_cursor: Option<String> = None;
        let mut file_count = 0u64;

        loop {
            let (records, next) = index.capability_files_page(file_cursor.as_deref(), usize::MAX);
            for record in records {
                if !path_is_at_or_below(&record.path, normalized_root) {
                    continue;
                }
                if self.is_protected(&record.path) {
                    blocked_targets.push(record.path);
                    continue;
                }
                if !is_image_path(&record.path) || record.size_bytes == 0 {
                    continue;
                }
                file_count += 1;
                if progress.is_cancelled() {
                    return Err(CapabilityAnalysisError::new(
                        "cancelled",
                        "similar photo analysis cancelled",
                    ));
                }
                progress.report(
                    CapabilityAnalysisPhase::Inspecting,
                    file_count,
                    file_count,
                    Some(record.path.clone()),
                );
                match read_photo(&record.path) {
    PhotoRead::Signature(signature) => photos.push(*signature),
                    PhotoRead::ReviewOnly { path, size_bytes, modified_at_ms, reason } => {
                        review_only.push(review_item(&path, size_bytes, modified_at_ms, &reason));
                    }
                }
            }
            match next {
                Some(cursor) => file_cursor = Some(cursor),
                None => break,
            }
        }

        let groups = group_photos(&photos, preset);
        let mut items = Vec::new();
        for group in groups {
            let keep_index = keep_index(&group);
            for (position, photo) in group.into_iter().enumerate() {
                let keep = position == keep_index;
                items.push(similar_item(photo, preset, keep));
            }
        }
        items.extend(review_only);
        let (items, next_cursor, truncated) =
            paginate_items(items, options.cursor.as_deref(), page_size);
        let target_paths: Vec<String> = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::ReviewNeeded)
            .filter_map(|item| item.delete_target.clone())
            .collect();
        let target_bytes = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::ReviewNeeded)
            .map(|item| item.size_bytes)
            .sum();
        progress.report(
            CapabilityAnalysisPhase::Grouping,
            items.len() as u64,
            items.len() as u64,
            None,
        );

        let grouped = group_items_by_direct_child(&items, normalized_root);
        let item_count = items.len() as u64;
        let total_bytes = items.iter().map(|item| item.size_bytes).sum();
        let kept_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::Keep)
            .count() as u64;
        let review_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::ReviewNeeded)
            .count() as u64;

        Ok(CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::SimilarPhotos,
            snapshot_id: index.snapshot_id.clone(),
            root_path: normalized_root.to_string(),
            analyzer_version: SIMILAR_PHOTOS_ANALYZER_VERSION.to_string(),
            generated_at_ms: index.scanned_at_ms,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary {
                item_count,
                total_bytes,
                safe_count: 0,
                review_count,
                kept_count,
                truncated,
            },
            groups: grouped,
            next_cursor,
            deletion_plan: DeletionPlan {
                snapshot_id: index.snapshot_id.clone(),
                target_count: target_paths.len() as u64,
                target_bytes,
                targets: target_paths,
                blocked_targets,
                requires_confirmation: true,
            },
            warnings: vec![],
        })
    }
}

fn is_image_path(path: &str) -> bool {
    let name = file_name(path).to_ascii_lowercase();
    name.rsplit_once('.')
        .map(|(_, ext)| IMAGE_EXTENSIONS.contains(&ext))
        .unwrap_or(false)
}

fn read_photo(path: &str) -> PhotoRead {
    let dimensions = match image::image_dimensions(path) {
        Ok(dimensions) => dimensions,
        Err(_) => {
            return PhotoRead::ReviewOnly {
                path: path.to_string(),
                size_bytes: file_size(path),
                modified_at_ms: None,
                reason: "decode_failed".to_string(),
            };
        }
    };
    let pixel_count = dimensions.0 as u64 * dimensions.1 as u64;
    if pixel_count > MAX_DECODE_PIXELS {
        return PhotoRead::ReviewOnly {
            path: path.to_string(),
            size_bytes: file_size(path),
            modified_at_ms: None,
            reason: "too_large".to_string(),
        };
    }
    let image = match image::open(Path::new(path)) {
        Ok(image) => image,
        Err(_) => {
            return PhotoRead::ReviewOnly {
                path: path.to_string(),
                size_bytes: file_size(path),
                modified_at_ms: None,
                reason: "decode_failed".to_string(),
            };
        }
    };
    let thumbnail = image.thumbnail(AHASH_SIZE, AHASH_SIZE).to_rgb8();
    let (width, height) = (image.width(), image.height());
    let ahash = average_hash(&thumbnail);
    let histogram = histogram(&image);
    PhotoRead::Signature(Box::new(PhotoSignature {
        path: path.to_string(),
        size_bytes: file_size(path),
        width,
        height,
        modified_at_ms: std::fs::metadata(path)
            .ok()
            .and_then(|metadata| metadata.modified().ok())
            .map(|time| {
                time.duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_millis() as i64)
                    .unwrap_or(0)
            }),
        ahash,
        histogram,
    }))
}

fn file_size(path: &str) -> u64 {
    std::fs::metadata(path)
        .map(|metadata| crate::model::allocated_file_size(&metadata))
        .unwrap_or(0)
}

fn average_hash(thumbnail: &image::RgbImage) -> u64 {
    let pixels: Vec<f64> = thumbnail
        .pixels()
        .map(|pixel| {
            (pixel[0] as f64 + pixel[1] as f64 + pixel[2] as f64) / 3.0
        })
        .collect();
    let mean = pixels.iter().sum::<f64>() / pixels.len().max(1) as f64;
    let mut hash = 0u64;
    for (position, value) in pixels.iter().enumerate() {
        if *value >= mean {
            hash |= 1u64 << position;
        }
    }
    hash
}

fn histogram(image: &image::DynamicImage) -> [u32; HIST_DIM] {
    let small = image.thumbnail(32, 32).to_rgb8();
    let mut histogram = [0u32; HIST_DIM];
    for pixel in small.pixels() {
        let r = (pixel[0] as usize * HIST_BINS / 256).min(HIST_BINS - 1);
        let g = (pixel[1] as usize * HIST_BINS / 256).min(HIST_BINS - 1);
        let b = (pixel[2] as usize * HIST_BINS / 256).min(HIST_BINS - 1);
        histogram[r * HIST_BINS * HIST_BINS + g * HIST_BINS + b] += 1;
    }
    histogram
}

fn hamming(a: u64, b: u64) -> u32 {
    (a ^ b).count_ones()
}

fn histogram_distance(a: &[u32; HIST_DIM], b: &[u32; HIST_DIM]) -> f64 {
    let total_a: u32 = a.iter().sum();
    let total_b: u32 = b.iter().sum();
    if total_a == 0 || total_b == 0 {
        return 1.0;
    }
    let mut distance = 0.0;
    for index in 0..HIST_DIM {
        let x = a[index] as f64 / total_a as f64;
        let y = b[index] as f64 / total_b as f64;
        distance += (x - y).abs();
    }
    distance
}

fn similar(a: &PhotoSignature, b: &PhotoSignature, preset: SimilarityPreset) -> bool {
    let ahash_distance = hamming(a.ahash, b.ahash);
    let histogram_distance = histogram_distance(&a.histogram, &b.histogram);
    // Solid-color images all share a degenerate all-ones aHash; fall back to
    // the color histogram so e.g. solid red and solid blue never match.
    if is_solid(&a.histogram) || is_solid(&b.histogram) {
        return histogram_distance < 0.05;
    }
    match preset {
        SimilarityPreset::Strict => ahash_distance <= 2 && histogram_distance < 0.5,
        SimilarityPreset::Balanced => {
            ahash_distance <= 8 || (ahash_distance <= 24 && histogram_distance < 0.25)
        }
        SimilarityPreset::Loose => ahash_distance <= 16 || histogram_distance < 0.3,
    }
}

fn is_solid(histogram: &[u32; HIST_DIM]) -> bool {
    let total: u32 = histogram.iter().sum();
    total > 0 && *histogram.iter().max().unwrap() as f64 / total as f64 >= 0.95
}

fn group_photos(
    photos: &[PhotoSignature],
    preset: SimilarityPreset,
) -> Vec<Vec<PhotoSignature>> {
    let mut groups: Vec<Vec<PhotoSignature>> = Vec::new();
    let mut assigned = vec![false; photos.len()];
    for index in 0..photos.len() {
        if assigned[index] {
            continue;
        }
        let mut members = vec![index];
        assigned[index] = true;
        for candidate in (index + 1)..photos.len() {
            if assigned[candidate] {
                continue;
            }
            if similar(&photos[index], &photos[candidate], preset) {
                members.push(candidate);
                assigned[candidate] = true;
            }
        }
        if members.len() >= 2 {
            groups.push(
                members
                    .into_iter()
                    .map(|position| photos[position].clone())
                    .collect(),
            );
        }
    }
    groups
}

fn keep_index(group: &[PhotoSignature]) -> usize {
    group
        .iter()
        .enumerate()
        .min_by(|(_, a), (_, b)| {
            let a_depth = a.path.matches('/').count();
            let b_depth = b.path.matches('/').count();
            a_depth
                .cmp(&b_depth)
                .then_with(|| a.path.cmp(&b.path))
                .then_with(|| b.modified_at_ms.cmp(&a.modified_at_ms))
        })
        .map(|(position, _)| position)
        .unwrap_or(0)
}

fn similar_item(photo: PhotoSignature, preset: SimilarityPreset, keep: bool) -> AnalysisItem {
    let mut evidence = vec![
        format!("size_bytes:{}", photo.size_bytes),
        format!("width:{}", photo.width),
        format!("height:{}", photo.height),
        format!("ahash:{:016x}", photo.ahash),
        format!("preset:{}", preset_name(preset)),
        format!("preset_version:{PHOTO_PRESET_VERSION}"),
    ];
    match photo.modified_at_ms {
        Some(modified_at_ms) => evidence.push(format!("modified_at_ms:{modified_at_ms}")),
        None => evidence.push("modified_at:unavailable".to_string()),
    }
    AnalysisItem {
        id: photo.path.clone(),
        path: photo.path.clone(),
        display_name: file_name(&photo.path),
        size_bytes: photo.size_bytes,
        is_directory: false,
        modified_at_ms: photo.modified_at_ms,
        recommendation: if keep {
            Recommendation::Keep
        } else {
            Recommendation::ReviewNeeded
        },
        confidence: AnalysisConfidence::Medium,
        reason: "similar_photo".to_string(),
        evidence,
        delete_target: if keep { None } else { Some(photo.path.clone()) },
        preview: Some(AnalysisPreview {
            kind: "image".to_string(),
            locatable: true,
        }),
    }
}

fn review_item(path: &str, size_bytes: u64, modified_at_ms: Option<i64>, reason: &str) -> AnalysisItem {
    AnalysisItem {
        id: path.to_string(),
        path: path.to_string(),
        display_name: file_name(path),
        size_bytes,
        is_directory: false,
        modified_at_ms,
        recommendation: Recommendation::ReviewNeeded,
        confidence: AnalysisConfidence::Low,
        reason: "similar_photo_decode_failed".to_string(),
        evidence: vec![format!("decode_failure:{reason}")],
        delete_target: None,
        preview: Some(AnalysisPreview {
            kind: "image".to_string(),
            locatable: true,
        }),
    }
}

fn preset_name(preset: SimilarityPreset) -> &'static str {
    match preset {
        SimilarityPreset::Strict => "strict",
        SimilarityPreset::Balanced => "balanced",
        SimilarityPreset::Loose => "loose",
    }
}

fn file_name(path: &str) -> String {
    path.rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(path)
        .to_string()
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::*;
    use crate::capability_registry::NoopProgressSink;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::ScanStats;
    use image::imageops;
    use image::{Rgb, RgbImage};

    fn save_png(temp: &TempDir, relative: &str, image: &RgbImage) -> String {
        let path = temp.path().join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        image.save(&path).expect("save png");
        path.to_string_lossy().to_string()
    }

    fn gradient(width: u32, height: u32) -> RgbImage {
        let mut image = RgbImage::new(width, height);
        for (x, y, pixel) in image.enumerate_pixels_mut() {
            *pixel = Rgb([
                ((x * 255 / width.max(1)) as u8),
                ((y * 255 / height.max(1)) as u8),
                (((x + y) * 255 / (width.max(1) + height.max(1))) as u8),
            ]);
        }
        image
    }

    fn solid(color: [u8; 3], width: u32, height: u32) -> RgbImage {
        RgbImage::from_pixel(width, height, Rgb(color))
    }

    fn index_for(root: &str, files: &[String]) -> SnapshotIndex {
        let mut builder = SnapshotIndexBuilder::new(root);
        for path in files {
            let metadata = std::fs::metadata(path).unwrap();
            builder.record_file_size(path, crate::model::allocated_file_size(&metadata));
        }
        builder.finish(
            "snapshot-1".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    fn analyze(
        index: &SnapshotIndex,
        root: &str,
        preset: SimilarityPreset,
    ) -> CapabilityAnalysisResult {
        SimilarPhotoAnalyzer::new(vec![])
            .analyze(
                index,
                root,
                &AnalysisOptions {
                    similarity_preset: preset,
                    ..AnalysisOptions::default()
                },
                &NoopProgressSink,
            )
            .expect("similar photo analysis")
    }

    #[test]
    fn groups_exact_duplicates_resized_and_rotated_variants() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let original = gradient(64, 64);
        let exact = save_png(&temp, "one/exact.png", &original);
        let copy = save_png(&temp, "one/copy.png", &original);
        let resized = save_png(&temp, "two/resized.png", &imageops::resize(
            &original,
            32,
            32,
            imageops::FilterType::Triangle,
        ));
        let rotated = save_png(&temp, "three/rotated.png", &imageops::rotate90(&original));
        let index = index_for(&root, &[exact, copy, resized, rotated]);

        let result = analyze(&index, &root, SimilarityPreset::Loose);

        assert_eq!(result.summary.item_count, 4);
        assert_eq!(result.summary.kept_count, 1);
        assert_eq!(result.summary.review_count, 3);
        assert_eq!(result.deletion_plan.target_count, 3);
    }

    #[test]
    fn strict_preset_requires_near_identical_hashes() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let a = save_png(&temp, "one/a.png", &gradient(64, 64));
        let b = save_png(&temp, "two/b.png", &solid([10, 20, 30], 64, 64));
        let index = index_for(&root, &[a, b]);

        let result = analyze(&index, &root, SimilarityPreset::Strict);

        assert_eq!(result.summary.item_count, 0, "unrelated photos must not group");
    }

    #[test]
    fn unrelated_images_do_not_group() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let a = save_png(&temp, "one/red.png", &solid([255, 0, 0], 64, 64));
        let b = save_png(&temp, "two/blue.png", &solid([0, 0, 255], 64, 64));
        let index = index_for(&root, &[a, b]);

        let result = analyze(&index, &root, SimilarityPreset::Loose);

        assert_eq!(result.summary.item_count, 0);
    }

    #[test]
    fn corrupt_and_unsupported_files_are_review_only() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let corrupt = temp.path().join("corrupt.png");
        std::fs::write(&corrupt, b"not a real png at all").unwrap();
        let corrupt = corrupt.to_string_lossy().to_string();
        let unsupported = save_png(&temp, "ok.png", &gradient(16, 16));
        let index = index_for(&root, &[corrupt.clone(), unsupported]);

        let result = analyze(&index, &root, SimilarityPreset::Balanced);

        let corrupt_item = result
            .groups
            .iter()
            .flat_map(|g| g.items.iter())
            .find(|item| item.path == corrupt)
            .expect("corrupt file must appear as review-only");
        assert_eq!(corrupt_item.recommendation, Recommendation::ReviewNeeded);
        assert_eq!(corrupt_item.delete_target, None);
        assert!(
            corrupt_item
                .evidence
                .iter()
                .any(|evidence| evidence.starts_with("decode_failure:"))
        );
        assert_eq!(result.deletion_plan.target_count, 0);
    }

    #[test]
    fn cancellation_aborts_cleanly() {
        struct CancelAfterFirst;
        impl CapabilityProgressSink for CancelAfterFirst {
            fn report(
                &self,
                _phase: CapabilityAnalysisPhase,
                _processed: u64,
                _total: u64,
                _current_path: Option<String>,
            ) {}

            fn is_cancelled(&self) -> bool {
                true
            }
        }

        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let a = save_png(&temp, "one/a.png", &gradient(16, 16));
        let index = index_for(&root, &[a]);

        let error = SimilarPhotoAnalyzer::new(vec![])
            .analyze(
                &index,
                &root,
                &AnalysisOptions::default(),
                &CancelAfterFirst,
            )
            .expect_err("cancelled analysis must fail");
        assert_eq!(error.code, "cancelled");
    }

    #[test]
    fn output_pagination_pages_similar_photos_without_overlap() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let original = gradient(64, 64);
        let a = save_png(&temp, "one/a.png", &original);
        let b = save_png(&temp, "two/b.png", &original);
        let index = index_for(&root, &[a, b]);

        let first = SimilarPhotoAnalyzer::new(vec![])
            .analyze(
                &index,
                &root,
                &AnalysisOptions {
                    page_size: 1,
                    ..AnalysisOptions::default()
                },
                &NoopProgressSink,
            )
            .unwrap();
        assert_eq!(first.summary.item_count, 1);
        assert!(first.summary.truncated);
        let cursor = first.next_cursor.expect("next cursor");

        let second = SimilarPhotoAnalyzer::new(vec![])
            .analyze(
                &index,
                &root,
                &AnalysisOptions {
                    page_size: 1,
                    cursor: Some(cursor),
                    ..AnalysisOptions::default()
                },
                &NoopProgressSink,
            )
            .unwrap();
        assert_eq!(second.summary.item_count, 1);
        assert!(!second.summary.truncated);
        assert_ne!(first.groups[0].items[0].path, second.groups[0].items[0].path);
    }
}
