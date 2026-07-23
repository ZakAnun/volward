use std::ffi::OsStr;
use std::path::Path;

use jwalk::{DirEntry, Error};

/// Directory names pruned during full-volume walks (devtools / VCS / build artifacts).
/// Does not skip cache-like paths (`Caches`, `.cache`, etc.).
pub const SKIP_DIR_NAMES: &[&str] = &[
    "node_modules",
    ".git",
    ".svn",
    ".hg",
    "__pycache__",
    "DerivedData",
    ".gradle",
    ".npm",
    ".yarn",
    "bower_components",
    ".terraform",
    ".venv",
    "venv",
    "target",
    "build",
    "dist",
    "out",
    ".cargo",
    ".next",
    ".nuxt",
    ".output",
    "Pods",
    "Carthage",
    "vendor",
    ".bundle",
    ".tox",
    ".mypy_cache",
    ".pytest_cache",
    "site-packages",
    ".Spotlight-V100",
    ".fseventsd",
    ".DocumentRevisions-V100",
];

pub fn is_skippable_dir_name(name: &OsStr) -> bool {
    name.to_str().is_some_and(|n| SKIP_DIR_NAMES.contains(&n))
}

pub fn is_protected_path(path: &Path, protected_prefixes: &[String]) -> bool {
    let path_str = path.to_string_lossy();
    protected_prefixes
        .iter()
        .any(|pfx| path_str.starts_with(pfx.as_str()))
}

/// Prevent jwalk from descending into protected or dev/build directories.
pub fn prune_child_directories(
    children: &mut [Result<DirEntry<((), ())>, Error>],
    protected_prefixes: &[String],
) {
    for entry in children.iter_mut() {
        let Ok(dir_entry) = entry else { continue };
        if !dir_entry.file_type.is_dir() {
            continue;
        }
        if is_skippable_dir_name(&dir_entry.file_name) {
            dir_entry.read_children_path = None;
            continue;
        }
        if is_protected_path(&dir_entry.path(), protected_prefixes) {
            dir_entry.read_children_path = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn skips_known_dir_names() {
        assert!(is_skippable_dir_name(OsStr::new("node_modules")));
        assert!(is_skippable_dir_name(OsStr::new(".git")));
        assert!(!is_skippable_dir_name(OsStr::new("Caches")));
        assert!(!is_skippable_dir_name(OsStr::new("Library")));
    }

    #[test]
    fn skips_macos_metadata_dirs() {
        assert!(is_skippable_dir_name(OsStr::new(".Spotlight-V100")));
        assert!(is_skippable_dir_name(OsStr::new(".fseventsd")));
        assert!(is_skippable_dir_name(OsStr::new(".DocumentRevisions-V100")));
    }

    #[test]
    fn does_not_skip_trash() {
        assert!(!is_skippable_dir_name(OsStr::new(".Trash")));
    }

    #[test]
    fn protects_system_prefixes() {
        assert!(is_protected_path(
            Path::new("/System/Library"),
            &["/System".to_string()]
        ));
        assert!(!is_protected_path(
            Path::new("/Users/me"),
            &["/System".to_string()]
        ));
    }
}
