//! Directory role classification for AI coverage tree (Phase 2 §4.4).

use crate::index::SnapshotIndex;

/// Bit on [`crate::index::DirectoryRecord::pruned_child_flags`] when walk pruned a VCS child (`.git`, etc.).
pub const PRUNED_VCS: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DirectoryRole {
    Unknown,
    StorageLike,
    ProjectRoot,
    ProjectLike,
    CacheLike,
}

/// Manifest filenames from spec Appendix A (exact names; globs handled separately).
const MANIFEST_EXACT: &[&str] = &[
    "Cargo.toml",
    "Cargo.lock",
    "package.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "package-lock.json",
    "go.mod",
    "go.sum",
    "pyproject.toml",
    "setup.py",
    "requirements.txt",
    "Gemfile",
    "Podfile",
    "Podfile.lock",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "Package.swift",
    "pubspec.yaml",
    "composer.json",
    "CMakeLists.txt",
    "meson.build",
];

const PROJECT_SUBDIR_NAMES: &[&str] = &["src", "lib", "apps", "packages", "Sources", "include"];

/// Classify a directory using direct children from the snapshot index (no filesystem I/O).
pub fn classify_directory_role(
    index: &SnapshotIndex,
    dir_path: &str,
) -> (DirectoryRole, Vec<String>) {
    let pruned = index.directory_pruned_child_flags(dir_path);
    if pruned & PRUNED_VCS != 0 {
        return (DirectoryRole::ProjectRoot, vec!["pruned:vcs".to_string()]);
    }

    let query = index.query_directory(dir_path, None, false, "name");
    let mut manifest_markers: Vec<String> = Vec::new();
    let mut doc_markers: Vec<String> = Vec::new();
    let mut subdir_markers: Vec<String> = Vec::new();

    for child in &query.direct_children {
        if child.is_directory {
            if PROJECT_SUBDIR_NAMES.iter().any(|&n| n == child.name) {
                subdir_markers.push(child.name.clone());
            }
            continue;
        }
        if is_manifest_filename(&child.name) {
            manifest_markers.push(child.name.clone());
        }
        if is_project_doc_filename(&child.name) {
            doc_markers.push(child.name.clone());
        }
    }

    if !manifest_markers.is_empty() {
        manifest_markers.sort();
        manifest_markers.dedup();
        return (DirectoryRole::ProjectRoot, manifest_markers);
    }

    if !doc_markers.is_empty() && !subdir_markers.is_empty() {
        let mut markers = doc_markers;
        markers.append(&mut subdir_markers);
        markers.sort();
        markers.dedup();
        return (DirectoryRole::ProjectLike, markers);
    }

    (DirectoryRole::Unknown, vec![])
}

/// Sorted unique directory paths classified as [`DirectoryRole::ProjectRoot`] or [`DirectoryRole::ProjectLike`].
pub fn collect_project_anchor_paths(index: &SnapshotIndex) -> Vec<String> {
    let mut anchors = Vec::new();
    let mut stack = vec![index.root_path.clone()];
    while let Some(dir) = stack.pop() {
        let (role, _) = classify_directory_role(index, &dir);
        if matches!(
            role,
            DirectoryRole::ProjectRoot | DirectoryRole::ProjectLike
        ) {
            anchors.push(dir.clone());
        }
        let query = index.query_directory(&dir, None, false, "name");
        for child in query.direct_children {
            if child.is_directory {
                stack.push(child.path);
            }
        }
    }
    anchors.sort();
    anchors.dedup();
    anchors
}

fn is_manifest_filename(name: &str) -> bool {
    MANIFEST_EXACT.iter().any(|&m| m == name)
        || name.ends_with(".sln")
        || name.ends_with(".xcodeproj")
}

fn is_project_doc_filename(name: &str) -> bool {
    name.starts_with("README") || name == "LICENSE" || name.starts_with("CONTRIBUTING")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::ScanStats;

    fn finish(builder: SnapshotIndexBuilder) -> SnapshotIndex {
        builder.finish(
            "snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    #[test]
    fn cargo_toml_child_is_project_root() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/myapp");
        builder.record_file_size("/root/myapp/Cargo.toml", 100);
        let index = finish(builder);

        let (role, markers) = classify_directory_role(&index, "/root/myapp");
        assert_eq!(role, DirectoryRole::ProjectRoot);
        assert!(markers.iter().any(|m| m == "Cargo.toml"));
    }

    #[test]
    fn readme_and_src_is_project_like() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/myapp/src");
        builder.record_file_size("/root/myapp/README.md", 50);
        let index = finish(builder);

        let (role, markers) = classify_directory_role(&index, "/root/myapp");
        assert_eq!(role, DirectoryRole::ProjectLike);
        assert!(markers.iter().any(|m| m.starts_with("README")));
        assert!(markers.iter().any(|m| m == "src"));
    }

    #[test]
    fn pruned_vcs_child_marks_project_root() {
        let mut builder = SnapshotIndexBuilder::new("/proj");
        builder.ensure_dir("/proj");
        builder.or_pruned_child_flags("/proj", PRUNED_VCS);
        let index = finish(builder);

        let (role, markers) = classify_directory_role(&index, "/proj");
        assert_eq!(role, DirectoryRole::ProjectRoot);
        assert!(markers.iter().any(|m| m == "pruned:vcs"));
    }

    #[test]
    fn neither_manifest_nor_project_signals_is_unknown() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/random");
        builder.record_file_size("/root/random/notes.txt", 10);
        let index = finish(builder);

        let (role, markers) = classify_directory_role(&index, "/root/random");
        assert_eq!(role, DirectoryRole::Unknown);
        assert!(markers.is_empty());
    }
}
