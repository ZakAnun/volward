//! C ABI for Flutter `dart:ffi` (scaffold). FRB codegen can replace this later.

mod ai;
mod capabilities;
mod delete;
mod index;
mod scan;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

use crate::VolwardEngine;

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .map(|c| c.into_raw())
        .unwrap_or(ptr::null_mut())
}

unsafe fn engine_ref<'a>(ptr: *mut VolwardEngine) -> Option<&'a VolwardEngine> {
    if ptr.is_null() {
        None
    } else {
        Some(&*ptr)
    }
}

unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}

#[cfg(test)]
mod export_tests {
    #[test]
    fn c_export_count_stays_at_baseline() {
        const SOURCES: [&str; 6] = [
            include_str!("mod.rs"),
            include_str!("scan.rs"),
            include_str!("index.rs"),
            include_str!("delete.rs"),
            include_str!("capabilities.rs"),
            include_str!("ai.rs"),
        ];
        let marker = concat!("#[no_", "mangle]");
        let count = SOURCES
            .iter()
            .map(|source| source.matches(marker).count())
            .sum::<usize>();
        assert_eq!(count, 72);
    }
}

#[no_mangle]
pub extern "C" fn volward_engine_create() -> *mut VolwardEngine {
    Box::into_raw(Box::new(VolwardEngine::new()))
}

#[no_mangle]
pub unsafe extern "C" fn volward_engine_free(ptr: *mut VolwardEngine) {
    if !ptr.is_null() {
        drop(Box::from_raw(ptr));
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_free_string(s: *mut c_char) {
    if !s.is_null() {
        let _ = CString::from_raw(s);
    }
}

#[cfg(test)]
mod ai_contract_tests {
    use super::ai::{
        volward_ai_batch_size, volward_ai_build_coverage_plan_json,
        volward_ai_build_request_json, volward_ai_build_tree_coverage_plan_json,
        volward_ai_next_coverage_page_json, volward_ai_next_scope_coverage_page_json,
        volward_ai_parse_response_json, volward_ai_resolve_coverage_group_json,
        volward_ai_tree_batch_size,
    };
    use super::scan::{volward_get_last_pause_error, volward_request_scan_pause};
    use super::{c_char, volward_free_string, VolwardEngine};
    use std::ffi::{CStr, CString};
    use volward_core::pause_store::FilePauseStore;

    unsafe fn take(ptr: *mut c_char) -> String {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        volward_free_string(ptr);
        s
    }

    #[test]
    fn build_request_json_round_trips() {
        let input = CString::new(r#"[{"path":"/a","size_bytes":1,"is_dir":false}]"#).unwrap();
        let out = unsafe { take(volward_ai_build_request_json(input.as_ptr())) };
        assert!(!out.starts_with("error:"), "got {out}");
        let body: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(body["model"], volward_ai::MODEL);
        assert_eq!(body["thinking"]["type"], "disabled");
    }

    #[test]
    fn request_scan_pause_returns_the_rust_pause_index_path() {
        let mut engine = VolwardEngine::new();
        let cache = tempfile::TempDir::new().unwrap();
        let root = CString::new("/Users/test/Downloads").unwrap();
        let cache_dir = CString::new(cache.path().to_string_lossy().as_bytes()).unwrap();

        let actual = unsafe {
            take(volward_request_scan_pause(
                &mut engine,
                root.as_ptr(),
                cache_dir.as_ptr(),
            ))
        };
        let expected = FilePauseStore::new(cache.path().join("pauses"))
            .index_path("/Users/test/Downloads")
            .to_string_lossy()
            .into_owned();

        assert_eq!(actual, expected);
        assert!(unsafe { volward_get_last_pause_error(&mut engine) }.is_null());
    }

    #[test]
    fn build_request_json_ignores_member_paths() {
        let input = CString::new(
            r#"[{"path":"/a","size_bytes":1,"is_dir":true,"member_paths":["/a/secret"]}]"#,
        )
        .unwrap();
        let out = unsafe { take(volward_ai_build_request_json(input.as_ptr())) };
        assert!(
            !out.contains("secret"),
            "member_paths leaked into request: {out}"
        );
    }

    #[test]
    fn parse_response_json_round_trips() {
        let upstream = r#"{"choices":[{"finish_reason":"stop","message":{"content":"[{\"path\":\"/a\",\"verdict\":\"keep\",\"confidence\":\"high\",\"reason\":\"x\"}]"}}]}"#;
        let body = CString::new(upstream).unwrap();
        let batch = CString::new(r#"[{"path":"/a","size_bytes":1,"is_dir":false}]"#).unwrap();
        let out = unsafe {
            take(volward_ai_parse_response_json(
                body.as_ptr(),
                batch.as_ptr(),
            ))
        };
        let arr: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(arr[0]["verdict"], "keep");
    }

    #[test]
    fn parse_response_json_degrades_truncated_body_using_batch() {
        let body =
            CString::new(r#"{"choices":[{"finish_reason":"length","message":{"content":"["}}]}"#)
                .unwrap();
        let batch = CString::new(r#"[{"path":"/a","size_bytes":1,"is_dir":false}]"#).unwrap();
        let out = unsafe {
            take(volward_ai_parse_response_json(
                body.as_ptr(),
                batch.as_ptr(),
            ))
        };
        let arr: serde_json::Value = serde_json::from_str(&out).unwrap();
        assert_eq!(arr[0]["path"], "/a");
        assert_eq!(arr[0]["verdict"], "review_needed");
    }

    #[test]
    fn parse_response_json_reports_null_pointers() {
        let batch = CString::new("[]").unwrap();
        let a = unsafe {
            take(volward_ai_parse_response_json(
                std::ptr::null(),
                batch.as_ptr(),
            ))
        };
        assert_eq!(a, "error:null response");
        let body = CString::new("{}").unwrap();
        let b = unsafe {
            take(volward_ai_parse_response_json(
                body.as_ptr(),
                std::ptr::null(),
            ))
        };
        assert_eq!(b, "error:null batch");
    }

    #[test]
    fn batch_size_matches_crate_constant() {
        assert_eq!(
            unsafe { volward_ai_batch_size() } as usize,
            volward_ai::BATCH_SIZE
        );
        assert_eq!(
            unsafe { volward_ai_tree_batch_size() } as usize,
            volward_ai::TREE_BATCH_SIZE
        );
    }

    #[test]
    fn coverage_ffi_round_trips_summary_page_and_group() {
        let _cache_guard = crate::engine::COVERAGE_CACHE_TEST_LOCK
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        use crate::engine::VolwardEngine;
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let mut engine = VolwardEngine::new();
        let mut builder = SnapshotIndexBuilder::new("/Users/x");
        for i in 0..90 {
            builder.record_file_size(
                &format!("/Users/x/Library/Caches/cursor/f{i}.bin"),
                (i + 1) as u64,
            );
        }
        let index = builder.finish(
            "ffi-coverage".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        let summary = unsafe {
            take(volward_ai_build_coverage_plan_json(
                &mut engine as *mut VolwardEngine,
                c"ffi-coverage".as_ptr(),
            ))
        };
        let summary_json: serde_json::Value = serde_json::from_str(&summary).unwrap();
        assert_eq!(summary_json["pre_classified_count"], 90);
        assert_eq!(summary_json["local_safe_files"], 90);
        assert_eq!(summary_json["total_unclassified"], 0);
        assert_eq!(summary_json["file_rows"], 0);
        assert_eq!(summary_json["group_rows"], 0);

        let plan_version = summary_json["plan_version"].as_u64().unwrap_or(1);
        let page = unsafe {
            take(volward_ai_next_coverage_page_json(
                &mut engine as *mut VolwardEngine,
                c"ffi-coverage".as_ptr(),
                plan_version,
                0,
                40,
            ))
        };
        let parsed: serde_json::Value = serde_json::from_str(&page).unwrap();
        assert_eq!(parsed["rows"].as_array().unwrap().len(), 0);
        assert_eq!(parsed["next_cursor"], serde_json::Value::Null);

        let group = unsafe {
            take(volward_ai_resolve_coverage_group_json(
                &mut engine as *mut VolwardEngine,
                c"ffi-coverage".as_ptr(),
                c"/Users/x/Library/Caches/cursor".as_ptr(),
            ))
        };
        let parsed_group: serde_json::Value = serde_json::from_str(&group).unwrap();
        assert_eq!(parsed_group["members"].as_array().unwrap().len(), 90);

        let tree_summary = unsafe {
            take(volward_ai_build_tree_coverage_plan_json(
                &mut engine as *mut VolwardEngine,
                c"ffi-coverage".as_ptr(),
            ))
        };
        let tree_json: serde_json::Value =
            serde_json::from_str(&tree_summary).unwrap();
        let tree_plan_version = tree_json["plan_version"].as_u64().unwrap_or(1);
        let scope = unsafe {
            take(volward_ai_next_scope_coverage_page_json(
                &mut engine as *mut VolwardEngine,
                c"ffi-coverage".as_ptr(),
                tree_plan_version,
                0,
                40,
            ))
        };
        let scope_json: serde_json::Value = serde_json::from_str(&scope).unwrap();
        assert_eq!(scope_json["rows"].as_array().unwrap().len(), 40);
        assert!(scope_json["next_cursor"].as_u64().is_some());
    }
}
