use std::collections::HashMap;

use crate::model::ScanTreeNode;

pub struct ScanTreeBuilder {
    root: ScanTreeNode,
    root_path: String,
    dir_paths: HashMap<String, ()>,
    dir_child_index: HashMap<String, HashMap<String, usize>>,
    aborted: bool,
}

impl ScanTreeBuilder {
    pub fn new(root_path: &str) -> Self {
        let root_path = normalize_path(root_path);
        let name = root_path
            .rsplit('/')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or(root_path.as_str())
            .to_string();
        let mut dir_paths = HashMap::new();
        dir_paths.insert(root_path.clone(), ());
        Self {
            root: ScanTreeNode {
                name,
                path: root_path.clone(),
                is_dir: true,
                size_bytes: 0,
                entry_id: None,
                children: Vec::new(),
            },
            root_path,
            dir_paths,
            dir_child_index: HashMap::new(),
            aborted: false,
        }
    }

    pub fn ensure_dir(&mut self, path: &str) {
        let path = normalize_path(path);
        if !is_under_root(&path, &self.root_path) {
            return;
        }
        self.ensure_dir_internal(&path);
    }

    pub fn insert_file(&mut self, path: &str, entry_id: Option<&str>, size: u64) {
        let path = normalize_path(path);
        if !is_under_root(&path, &self.root_path) {
            return;
        }

        let name = path
            .rsplit('/')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or(path.as_str())
            .to_string();

        let parent_path = parent_path(&path, &self.root_path);
        self.ensure_dir_internal(&parent_path);

        let parent = self.find_dir_mut(&parent_path);
        parent.children.push(ScanTreeNode {
            name,
            path,
            is_dir: false,
            size_bytes: size,
            entry_id: entry_id.map(str::to_string),
            children: Vec::new(),
        });
    }

    /// Replace the children of `dir_path` with a cloned cached subtree.
    pub fn graft_subtree(&mut self, dir_path: &str, source: &ScanTreeNode) {
        let dir_path = normalize_path(dir_path);
        if !source.is_dir || normalize_path(&source.path) != dir_path {
            return;
        }
        self.ensure_dir_internal(&dir_path);
        self.find_dir_mut(&dir_path).children = source.children.clone();
        self.rebuild_dir_indexes();
    }

    pub fn finalize(mut self) -> ScanTreeNode {
        aggregate_sizes(&mut self.root);
        self.root
    }

    /// Non-destructive snapshot of the tree built so far. Unlike [`finalize`],
    /// this can be called repeatedly while the builder keeps accepting more
    /// `insert_file`/`ensure_dir`/`graft_subtree` calls afterwards.
    pub fn peek_snapshot(&self) -> ScanTreeNode {
        let mut clone = self.root.clone();
        aggregate_sizes(&mut clone);
        clone
    }

    pub fn was_aborted(&self) -> bool {
        self.aborted
    }

    fn rebuild_dir_indexes(&mut self) {
        self.dir_paths.clear();
        self.dir_child_index.clear();
        collect_dir_indexes(&self.root, &mut self.dir_paths, &mut self.dir_child_index);
    }

    fn ensure_dir_internal(&mut self, path: &str) {
        if self.dir_paths.contains_key(path) {
            return;
        }

        let relative = relative_path(&self.root_path, path);
        if relative.is_empty() {
            self.dir_paths.insert(path.to_string(), ());
            return;
        }

        let segments: Vec<&str> = relative.split('/').filter(|s| !s.is_empty()).collect();
        let mut current = &mut self.root;
        let mut current_path = self.root_path.clone();

        for segment in segments {
            let parent_path_for_index = current_path.clone();
            current_path = format!("{current_path}/{segment}");
            if self.dir_paths.contains_key(&current_path) {
                current = Self::find_dir_child_mut(
                    &self.dir_child_index,
                    &parent_path_for_index,
                    current,
                    segment,
                )
                .expect("indexed dir must exist in tree");
                continue;
            }

            current.children.push(ScanTreeNode {
                name: segment.to_string(),
                path: current_path.clone(),
                is_dir: true,
                size_bytes: 0,
                entry_id: None,
                children: Vec::new(),
            });
            self.dir_paths.insert(current_path.clone(), ());
            let last = current.children.len() - 1;
            self.dir_child_index
                .entry(parent_path_for_index)
                .or_default()
                .insert(segment.to_string(), last);
            current = &mut current.children[last];
        }
    }

    fn find_dir_mut(&mut self, path: &str) -> &mut ScanTreeNode {
        if path == self.root_path {
            return &mut self.root;
        }

        let relative = relative_path(&self.root_path, path);
        let segments: Vec<&str> = relative.split('/').filter(|s| !s.is_empty()).collect();
        let mut current = &mut self.root;
        let mut current_path = self.root_path.clone();

        for segment in segments {
            let parent_path = current_path.clone();
            current_path = format!("{current_path}/{segment}");
            current =
                Self::find_dir_child_mut(&self.dir_child_index, &parent_path, current, segment)
                    .expect("directory path must exist before inserting file");
        }

        current
    }

    fn find_dir_child_mut<'a>(
        dir_child_index: &HashMap<String, HashMap<String, usize>>,
        parent_path: &str,
        parent: &'a mut ScanTreeNode,
        name: &str,
    ) -> Option<&'a mut ScanTreeNode> {
        if let Some(idx) = dir_child_index
            .get(parent_path)
            .and_then(|children| children.get(name))
        {
            return parent
                .children
                .get_mut(*idx)
                .filter(|child| child.is_dir && child.name == name);
        }

        parent
            .children
            .iter_mut()
            .find(|child| child.is_dir && child.name == name)
    }
}

/// Find a directory subtree by its normalized absolute path.
pub fn find_subtree<'a>(root: &'a ScanTreeNode, path: &str) -> Option<&'a ScanTreeNode> {
    let path = normalize_path(path);
    if normalize_path(&root.path) == path {
        return Some(root);
    }
    root.children
        .iter()
        .filter(|child| child.is_dir)
        .find_map(|child| find_subtree(child, &path))
}

fn collect_dir_indexes(
    node: &ScanTreeNode,
    dir_paths: &mut HashMap<String, ()>,
    dir_child_index: &mut HashMap<String, HashMap<String, usize>>,
) {
    if !node.is_dir {
        return;
    }
    dir_paths.insert(node.path.clone(), ());
    for (index, child) in node.children.iter().enumerate() {
        if child.is_dir {
            dir_child_index
                .entry(node.path.clone())
                .or_default()
                .insert(child.name.clone(), index);
            collect_dir_indexes(child, dir_paths, dir_child_index);
        }
    }
}

fn normalize_path(path: &str) -> String {
    if path.len() > 1 && path.ends_with('/') {
        path[..path.len() - 1].to_string()
    } else {
        path.to_string()
    }
}

fn parent_path(path: &str, root_path: &str) -> String {
    if path == root_path {
        return root_path.to_string();
    }
    path.rfind('/')
        .map(|idx| path[..idx].to_string())
        .unwrap_or_else(|| root_path.to_string())
}

fn is_under_root(path: &str, root_path: &str) -> bool {
    let path = normalize_path(path);
    let root_path = normalize_path(root_path);
    path == root_path
        || (path.starts_with(&root_path)
            && (root_path == "/" || path.as_bytes().get(root_path.len()) == Some(&b'/')))
}

fn relative_path(root_path: &str, path: &str) -> String {
    let path = normalize_path(path);
    let root_path = normalize_path(root_path);
    if path == root_path {
        return String::new();
    }
    if !is_under_root(&path, &root_path) {
        return String::new();
    }
    if root_path == "/" {
        return path.strip_prefix('/').unwrap_or(&path).to_string();
    }
    path.strip_prefix(&format!("{root_path}/"))
        .unwrap_or("")
        .to_string()
}

fn aggregate_sizes(node: &mut ScanTreeNode) {
    if !node.is_dir {
        return;
    }
    let mut total = 0u64;
    for child in &mut node.children {
        aggregate_sizes(child);
        total = total.saturating_add(child.size_bytes);
    }
    node.size_bytes = total;
}

// Directory ordering for display is applied in the Flutter UI (`_sortTree`).

#[cfg(test)]
mod tests {
    use super::*;

    fn count_files(node: &ScanTreeNode) -> usize {
        if !node.is_dir {
            return 1;
        }
        node.children.iter().map(count_files).sum()
    }

    fn count_dirs(node: &ScanTreeNode) -> usize {
        if !node.is_dir {
            return 0;
        }
        1 + node.children.iter().map(count_dirs).sum::<usize>()
    }

    #[test]
    fn inserts_all_files_without_cap() {
        let mut b = ScanTreeBuilder::new("/r");
        for i in 0..1000 {
            b.insert_file(&format!("/r/f{i}"), Some(&format!("id{i}")), 1);
        }
        assert!(!b.was_aborted());
        let root = b.finalize();
        assert_eq!(count_files(&root), 1000);
    }

    #[test]
    fn ensure_dir_creates_nested_directories() {
        let mut b = ScanTreeBuilder::new("/root");
        b.ensure_dir("/root/a/b/c");
        let root = b.finalize();
        assert_eq!(count_dirs(&root), 4);
        assert_eq!(root.children.len(), 1);
        assert_eq!(root.children[0].name, "a");
    }

    #[test]
    fn finalize_preserves_children_without_sorting() {
        let mut b = ScanTreeBuilder::new("/root");
        b.insert_file("/root/small.txt", Some("s"), 10);
        b.insert_file("/root/large.txt", Some("l"), 100);
        b.ensure_dir("/root/sub");
        let root = b.finalize();
        assert_eq!(root.children.len(), 3);
        assert!(root.children.iter().any(|c| c.is_dir && c.name == "sub"));
        assert!(root
            .children
            .iter()
            .any(|c| !c.is_dir && c.size_bytes == 100));
        assert!(root
            .children
            .iter()
            .any(|c| !c.is_dir && c.size_bytes == 10));
    }

    #[test]
    fn inserts_many_siblings_under_one_dir() {
        let mut b = ScanTreeBuilder::new("/root");
        b.ensure_dir("/root/sub");
        for i in 0..5000 {
            b.insert_file(&format!("/root/sub/f{i}"), Some(&format!("id{i}")), 1);
        }
        assert!(!b.was_aborted());
        let root = b.finalize();
        let sub = root
            .children
            .iter()
            .find(|c| c.is_dir && c.name == "sub")
            .expect("sub dir");
        assert_eq!(sub.children.len(), 5000);
        assert_eq!(count_files(&root), 5000);
    }

    #[test]
    fn aggregate_sizes_sums_descendants() {
        let mut b = ScanTreeBuilder::new("/root");
        b.insert_file("/root/a/one", Some("1"), 5);
        b.insert_file("/root/a/two", Some("2"), 7);
        let root = b.finalize();
        let dir_a = root
            .children
            .iter()
            .find(|c| c.is_dir && c.name == "a")
            .expect("dir a");
        assert_eq!(dir_a.size_bytes, 12);
        assert_eq!(root.size_bytes, 12);
    }

    #[test]
    fn relative_path_does_not_panic_for_false_prefix() {
        assert_eq!(relative_path("/Users/me", "/Users/meeting/x"), "");
        assert_eq!(relative_path("/Users/me", "/Users/me"), "");
        assert_eq!(relative_path("/Users/me", "/Users/me/docs/a"), "docs/a");
    }

    #[test]
    fn relative_path_handles_root_volume() {
        assert_eq!(relative_path("/", "/Users/foo"), "Users/foo");
        assert_eq!(relative_path("/", "/"), "");
    }

    #[test]
    fn grafts_cached_subtree_children() {
        let mut builder = ScanTreeBuilder::new("/root");
        builder.ensure_dir("/root/cached");
        let source = ScanTreeNode {
            name: "cached".to_string(),
            path: "/root/cached".to_string(),
            is_dir: true,
            size_bytes: 7,
            entry_id: None,
            children: vec![ScanTreeNode {
                name: "file".to_string(),
                path: "/root/cached/file".to_string(),
                is_dir: false,
                size_bytes: 7,
                entry_id: Some("cached-id".to_string()),
                children: vec![],
            }],
        };

        builder.graft_subtree("/root/cached", &source);
        let root = builder.finalize();
        let cached = find_subtree(&root, "/root/cached").expect("grafted directory");
        assert_eq!(cached.children.len(), 1);
        assert_eq!(cached.children[0].entry_id.as_deref(), Some("cached-id"));
    }

    #[test]
    fn peek_snapshot_is_non_destructive() {
        let mut b = ScanTreeBuilder::new("/root");
        b.insert_file("/root/a.txt", Some("a"), 10);

        let peek1 = b.peek_snapshot();
        assert_eq!(peek1.size_bytes, 10);
        assert_eq!(peek1.children.len(), 1);

        // Builder must remain fully usable after a peek.
        b.insert_file("/root/b.txt", Some("b"), 20);
        let peek2 = b.peek_snapshot();
        assert_eq!(peek2.size_bytes, 30);
        assert_eq!(peek2.children.len(), 2);

        let final_tree = b.finalize();
        assert_eq!(final_tree.size_bytes, 30);
        assert_eq!(final_tree.children.len(), 2);
    }
}
