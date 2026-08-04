use std::collections::HashMap;
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

use serde::{Deserialize, Serialize};

/// Interns strings to dense `u32` IDs. Each unique string is stored exactly
/// once; all other structures reference it by `u32` ID, eliminating the
/// 3–5× duplication that occurred when the same path appeared as a HashMap
/// key, a `parent_path` field, a `children` vector entry, etc.
///
/// The table is serialized as an ordered `Vec<Box<str>>` so IDs are stable
/// across save/load. The `lookup` map stores only hashed IDs, never full
/// strings, and is rebuilt on demand after deserialization.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct StringTable {
    /// Indexed by `u32` ID — the position in this vector IS the ID.
    strings: Vec<Box<str>>,
    /// Reverse lookup for dedup on `intern`.
    #[serde(skip)]
    lookup: HashMap<u64, Vec<u32>>,
}

impl StringTable {
    fn hash_str(s: &str) -> u64 {
        let mut hasher = DefaultHasher::new();
        s.hash(&mut hasher);
        hasher.finish()
    }

    /// Intern a string, returning its `u32` ID. If the string was already
    /// interned, returns the existing ID without allocating.
    pub fn intern(&mut self, s: &str) -> u32 {
        let hash = Self::hash_str(s);
        if let Some(bucket) = self.lookup.get(&hash) {
            for &id in bucket {
                if self
                    .strings
                    .get(id as usize)
                    .is_some_and(|stored| stored.as_ref() == s)
                {
                    return id;
                }
            }
        }
        let id = self.strings.len() as u32;
        let owned: Box<str> = s.into();
        self.strings.push(owned);
        self.lookup.entry(hash).or_default().push(id);
        id
    }

    /// Read-only lookup — returns the ID if the string was previously
    /// interned, without inserting. Used at query time.
    pub fn get_id(&self, s: &str) -> Option<u32> {
        let hash = Self::hash_str(s);
        self.lookup.get(&hash).and_then(|bucket| {
            bucket.iter().copied().find(|&id| {
                self.strings
                    .get(id as usize)
                    .is_some_and(|stored| stored.as_ref() == s)
            })
        })
    }

    /// Resolve a `u32` ID back to its string slice.
    ///
    /// Returns `""` for out-of-range IDs so corrupted/partial caches cannot
    /// panic across the FFI boundary; callers that need strictness should
    /// validate IDs before resolve.
    pub fn resolve(&self, id: u32) -> &str {
        self.strings
            .get(id as usize)
            .map(AsRef::as_ref)
            .unwrap_or("")
    }

    /// Number of interned strings.
    pub fn len(&self) -> usize {
        self.strings.len()
    }

    pub fn is_empty(&self) -> bool {
        self.strings.is_empty()
    }

    /// Build a table from serialized strings without cloning them.
    pub fn from_strings(strings: Vec<Box<str>>) -> Self {
        let mut table = Self {
            strings,
            lookup: HashMap::new(),
        };
        table.rebuild_lookup();
        table.compact();
        table
    }

    /// Trim excess capacity now that the table is frozen.
    pub fn compact(&mut self) {
        self.strings.shrink_to_fit();
        for bucket in self.lookup.values_mut() {
            bucket.shrink_to_fit();
        }
        self.lookup.shrink_to_fit();
    }

    /// Iterate over all interned strings in ID order.
    pub fn iter(&self) -> impl Iterator<Item = (u32, &str)> + '_ {
        self.strings
            .iter()
            .enumerate()
            .map(|(i, s)| (i as u32, s.as_ref()))
    }

    /// Rebuild the reverse lookup map after deserialization. Must be called
    /// before any `intern()` call on a deserialized table.
    pub fn rebuild_lookup(&mut self) {
        self.lookup.clear();
        for (i, s) in self.strings.iter().enumerate() {
            self.lookup
                .entry(Self::hash_str(s))
                .or_default()
                .push(i as u32);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intern_dedup_returns_same_id() {
        let mut t = StringTable::default();
        let a = t.intern("/Users/foo");
        let b = t.intern("/Users/foo");
        let c = t.intern("/Users/bar");
        assert_eq!(a, b);
        assert_ne!(a, c);
        assert_eq!(t.len(), 2);
    }

    #[test]
    fn resolve_roundtrip() {
        let mut t = StringTable::default();
        let id = t.intern("/tmp/test");
        assert_eq!(t.resolve(id), "/tmp/test");
    }

    #[test]
    fn get_id_returns_none_for_missing() {
        let t = StringTable::default();
        assert_eq!(t.get_id("/nonexistent"), None);
    }

    #[test]
    fn serde_roundtrip_preserves_ids() {
        let mut t = StringTable::default();
        let a = t.intern("/Users/foo");
        let b = t.intern("/Users/bar");
        let _c = t.intern("/Users/baz");

        let json = serde_json::to_string(&t).expect("serialize");
        let mut t2: StringTable = serde_json::from_str(&json).expect("deserialize");
        t2.rebuild_lookup();

        assert_eq!(t2.resolve(a), "/Users/foo");
        assert_eq!(t2.resolve(b), "/Users/bar");
        assert_eq!(t2.get_id("/Users/baz"), Some(2));
        assert_eq!(t2.len(), 3);

        // Can intern new strings after rebuild without collision.
        let d = t2.intern("/Users/new");
        assert_eq!(d, 3);
    }

    #[test]
    fn empty_table() {
        let t = StringTable::default();
        assert!(t.is_empty());
        assert_eq!(t.len(), 0);
    }
}
