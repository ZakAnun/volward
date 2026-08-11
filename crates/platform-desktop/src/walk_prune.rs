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
    let path_str = normalize_path_str(&path.to_string_lossy());
    protected_prefixes
        .iter()
        .any(|pfx| path_is_at_or_below(&path_str, &normalize_path_str(pfx)))
}

fn normalize_path_str(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    if normalized.len() > 1 && normalized.ends_with('/') && !is_windows_drive_root(&normalized) {
        normalized[..normalized.len() - 1].to_string()
    } else {
        normalized
    }
}

fn path_is_at_or_below(path: &str, root: &str) -> bool {
    if root.is_empty() {
        return false;
    }
    let windows_style = has_windows_drive_prefix(path)
        || has_windows_drive_prefix(root)
        || path.starts_with("//")
        || root.starts_with("//");
    let same_or_prefixed = if windows_style {
        path.eq_ignore_ascii_case(root)
            || (path.len() > root.len()
                && path.as_bytes()[..root.len()].eq_ignore_ascii_case(root.as_bytes())
                && (root == "/"
                    || is_windows_drive_root(root)
                    || path.as_bytes().get(root.len()) == Some(&b'/')))
    } else {
        path == root
            || (path.starts_with(root)
                && (root == "/" || path.as_bytes().get(root.len()) == Some(&b'/')))
    };
    same_or_prefixed
}

fn has_windows_drive_prefix(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

fn is_windows_drive_root(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() == 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
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
        assert!(!is_protected_path(
            Path::new("/Systematic/file"),
            &["/System".to_string()]
        ));
    }

    #[test]
    fn protects_windows_paths_case_insensitively_with_boundary() {
        assert!(is_protected_path(
            Path::new(r"c:\windows\System32"),
            &["C:/Windows".to_string()]
        ));
        assert!(is_protected_path(
            Path::new(r"D:\Windows\System32"),
            &["d:/WINDOWS".to_string()]
        ));
        assert!(!is_protected_path(
            Path::new(r"C:\Windows.old"),
            &["C:/Windows".to_string()]
        ));
    }
}
