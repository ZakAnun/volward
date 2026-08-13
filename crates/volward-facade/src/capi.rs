//! C ABI for Flutter `dart:ffi` (scaffold). FRB codegen can replace this later.

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

#[no_mangle]
pub unsafe extern "C" fn volward_probe_capabilities_json(
    engine: *mut VolwardEngine,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    to_c_string(e.probe_capabilities_json())
}

#[no_mangle]
pub unsafe extern "C" fn volward_is_deep_scan_ready(engine: *mut VolwardEngine) -> bool {
    engine_ref(engine)
        .map(|e| e.is_deep_scan_ready())
        .unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_start_scan(
    engine: *mut VolwardEngine,
    job_id: *const c_char,
    roots_json: *const c_char,
) -> *mut c_char {
    volward_start_scan_with_options(engine, job_id, roots_json, false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_start_scan_with_options(
    engine: *mut VolwardEngine,
    job_id: *const c_char,
    roots_json: *const c_char,
    incremental: bool,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let job = cstr_to_string(job_id).unwrap_or_else(|| "flutter-job".to_string());
    let roots: Vec<String> = cstr_to_string(roots_json)
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    to_c_string(e.start_scan(job, roots, incremental))
}

#[no_mangle]
pub unsafe extern "C" fn volward_start_scan_async(
    engine: *mut VolwardEngine,
    job_id: *const c_char,
    roots_json: *const c_char,
) -> *mut c_char {
    volward_start_scan_async_with_options(engine, job_id, roots_json, false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_start_scan_async_with_options(
    engine: *mut VolwardEngine,
    job_id: *const c_char,
    roots_json: *const c_char,
    incremental: bool,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let job = cstr_to_string(job_id).unwrap_or_else(|| "flutter-job".to_string());
    let roots: Vec<String> = cstr_to_string(roots_json)
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    to_c_string(e.start_scan_async(job, roots, incremental))
}

#[no_mangle]
pub unsafe extern "C" fn volward_is_scan_running(engine: *mut VolwardEngine) -> bool {
    engine_ref(engine)
        .map(|e| e.is_scan_running())
        .unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_cancel_scan(engine: *mut VolwardEngine) {
    if let Some(e) = engine_ref(engine) {
        e.cancel_scan();
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_snapshot_json(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    e.get_last_snapshot_json()
        .map(|s| to_c_string(s))
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_snapshot_catalog_json(
    engine: *mut VolwardEngine,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    e.get_last_snapshot_catalog_json()
        .map(to_c_string)
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_progress_json(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    e.get_last_progress_json()
        .map(|s| to_c_string(s))
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn volward_set_last_snapshot_json(
    engine: *mut VolwardEngine,
    snapshot_json: *const c_char,
) -> bool {
    let Some(e) = engine_ref(engine) else {
        return false;
    };
    cstr_to_string(snapshot_json)
        .map(|json| e.set_last_snapshot_json(&json).is_ok())
        .unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_write_last_snapshot_to_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    match e.write_last_snapshot_to_path(&path) {
        Ok(id) => to_c_string(id),
        Err(msg) => to_c_string(msg),
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_write_last_snapshot_catalog_to_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    match e.write_last_snapshot_catalog_to_path(&path) {
        Ok(id) => to_c_string(id),
        Err(msg) => to_c_string(msg),
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_load_snapshot_catalog_from_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    match e.load_snapshot_catalog_from_path(&path) {
        Ok(json) => to_c_string(json),
        Err(msg) => to_c_string(msg),
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_write_last_checkpoint_to_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    match e.write_last_checkpoint_to_path(&path) {
        Ok(id) => to_c_string(id),
        Err(msg) => to_c_string(msg),
    }
}

/// Protobuf variant of `volward_write_last_snapshot_to_path`. Writes the
/// snapshot to `path` as protobuf bytes via an atomic temp+rename.
#[no_mangle]
pub unsafe extern "C" fn volward_write_last_snapshot_to_path_pb(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    match e.write_last_snapshot_to_path_pb(&path) {
        Ok(id) => to_c_string(id),
        Err(msg) => to_c_string(msg),
    }
}

/// Protobuf variant of `volward_write_last_checkpoint_to_path`. Writes the
/// last checkpoint to `path` as protobuf bytes via an atomic temp+rename.
#[no_mangle]
pub unsafe extern "C" fn volward_write_last_checkpoint_to_path_pb(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    match e.write_last_checkpoint_to_path_pb(&path) {
        Ok(id) => to_c_string(id),
        Err(msg) => to_c_string(msg),
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_quick_list_dir_json(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let Some(path) = cstr_to_string(path) else {
        return to_c_string("error:null path".to_string());
    };
    to_c_string(e.quick_list_dir_json(&path))
}

#[no_mangle]
pub unsafe extern "C" fn volward_load_last_snapshot_from_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> bool {
    let Some(e) = engine_ref(engine) else {
        return false;
    };
    cstr_to_string(path)
        .map(|p| e.load_last_snapshot_from_path(&p).is_ok())
        .unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_open_permission_settings(engine: *mut VolwardEngine) -> bool {
    engine_ref(engine)
        .map(|e| e.open_permission_settings().is_ok())
        .unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_delete_entries_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    entry_ids_json: *const c_char,
    dry_run: bool,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    let entry_ids: Vec<String> = cstr_to_string(entry_ids_json)
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    to_c_string(e.delete_entries_json(&snapshot_id, entry_ids, dry_run))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_build_candidates_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.build_ai_candidates_json(&snapshot_id))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_start_build_candidates_async(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.start_build_ai_candidates_async(snapshot_id))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_is_candidates_building(engine: *mut VolwardEngine) -> bool {
    let Some(e) = engine_ref(engine) else {
        return false;
    };
    e.is_ai_candidates_building()
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_get_candidates_json(
    engine: *mut VolwardEngine,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    to_c_string(e.get_ai_candidates_json())
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_save_result_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    result_json: *const c_char,
) -> bool {
    let Some(e) = engine_ref(engine) else {
        return false;
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    let result_json = cstr_to_string(result_json).unwrap_or_default();
    e.save_ai_result_json(&snapshot_id, &result_json)
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_load_result_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.load_ai_result_json(&snapshot_id))
}

#[no_mangle]
pub unsafe extern "C" fn volward_empty_trash_json(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    match e.empty_trash() {
        Ok(report) => {
            to_c_string(serde_json::to_string(&report).unwrap_or_else(|_| "{}".to_string()))
        }
        Err(msg) => to_c_string(serde_json::json!({ "error": msg }).to_string()),
    }
}

unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}

// ---------------------------------------------------------------------------
// Catalog index APIs (Design §5.3 — Dart queries these instead of hydrating)
// ---------------------------------------------------------------------------

/// Query direct children of `path` with optional filter/sort.
/// Returns JSON `SnapshotQueryResult` or `{"error":"…"}`.
/// Pure in-memory — does NOT trigger a file-system scan.
#[no_mangle]
pub unsafe extern "C" fn volward_query_directory_json(
    engine: *mut VolwardEngine,
    path: *const c_char,
    category_filter: *const c_char, // may be null
    deletable_only: bool,
    sort_mode: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let path = match cstr_to_string(path) {
        Some(p) => p,
        None => return to_c_string(r#"{"error":"null path"}"#.to_string()),
    };
    let category_filter = cstr_to_string(category_filter);
    let sort_mode = cstr_to_string(sort_mode).unwrap_or_else(|| "size_desc".to_string());
    match e.query_directory_json(
        &path,
        category_filter.as_deref(),
        deletable_only,
        &sort_mode,
    ) {
        Ok(json) => to_c_string(json),
        Err(msg) => to_c_string(serde_json::json!({"error": msg}).to_string()),
    }
}

/// Re-query the existing index for `path` — pure in-memory, no scan.
/// Returns JSON `SnapshotQueryResult` or `{"error":"…"}`.
#[no_mangle]
pub unsafe extern "C" fn volward_refresh_directory(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let path = match cstr_to_string(path) {
        Some(p) => p,
        None => return to_c_string(r#"{"error":"null path"}"#.to_string()),
    };
    match e.refresh_directory(&path) {
        Ok(json) => to_c_string(json),
        Err(msg) => to_c_string(serde_json::json!({"error": msg}).to_string()),
    }
}

/// Splices a freshly scanned subtree (peek/scoped scan result) into the
/// catalog index, replacing the directory at `target_path`, and bumps the
/// index version. `subtree_json` is `{"tree": ScanTreeNode, "entries": […]}`.
/// Returns the new version as a JSON number string, or `{"error":"…"}`.
#[no_mangle]
pub unsafe extern "C" fn volward_replace_directory_with_subtree(
    engine: *mut VolwardEngine,
    target_path: *const c_char,
    subtree_json: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let Some(target_path) = cstr_to_string(target_path) else {
        return to_c_string(r#"{"error":"null target_path"}"#.to_string());
    };
    let Some(subtree_json) = cstr_to_string(subtree_json) else {
        return to_c_string(r#"{"error":"null subtree_json"}"#.to_string());
    };
    match e.replace_directory_with_subtree_json(&target_path, &subtree_json) {
        Ok(version) => to_c_string(version.to_string()),
        Err(msg) => to_c_string(serde_json::json!({"error": msg}).to_string()),
    }
}

/// Load a persisted index file into the engine.
/// Returns true on success.
#[no_mangle]
pub unsafe extern "C" fn volward_load_index_from_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> bool {
    let Some(e) = engine_ref(engine) else {
        return false;
    };
    let Some(path) = cstr_to_string(path) else {
        return false;
    };
    e.load_index_from_path(&path).is_ok()
}

/// Start loading a persisted index/snapshot on a Rust worker thread.
/// Returns `ok` on start, `busy:...` while another load is running, or `error:...`.
#[no_mangle]
pub unsafe extern "C" fn volward_start_load_index_from_path_async(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let path = match cstr_to_string(path) {
        Some(p) => p,
        None => return to_c_string("error:null path".to_string()),
    };
    to_c_string(e.start_load_index_from_path_async(path))
}

#[no_mangle]
pub unsafe extern "C" fn volward_is_index_loading(engine: *mut VolwardEngine) -> bool {
    engine_ref(engine)
        .map(|e| e.is_index_loading())
        .unwrap_or(false)
}

#[no_mangle]
pub unsafe extern "C" fn volward_invalidate_index_load(engine: *mut VolwardEngine) {
    if let Some(e) = engine_ref(engine) {
        e.invalidate_index_load();
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_index_load_error(
    engine: *mut VolwardEngine,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    match e.get_last_index_load_error() {
        Some(error) => to_c_string(error),
        None => ptr::null_mut(),
    }
}

/// Persist the current index to `path`.
/// Returns the snapshot_id on success, or `error:…` on failure.
#[no_mangle]
pub unsafe extern "C" fn volward_write_last_index_to_path(
    engine: *mut VolwardEngine,
    path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let path = match cstr_to_string(path) {
        Some(p) => p,
        None => return to_c_string("error:null path".to_string()),
    };
    match e.write_last_index_to_path(&path) {
        Ok(id) => to_c_string(id),
        Err(msg) => to_c_string(msg),
    }
}

/// Returns lightweight metadata for the current index.
/// Returns JSON summary or `{"error":"…"}`.
#[no_mangle]
pub unsafe extern "C" fn volward_get_index_summary_json(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    match e.get_index_summary_json() {
        Ok(json) => to_c_string(json),
        Err(msg) => to_c_string(serde_json::json!({"error": msg}).to_string()),
    }
}

/// Returns the current catalog version counter as a u64.
/// Dart uses this as `SnapshotQueryKey.version` for cache alignment.
#[no_mangle]
pub unsafe extern "C" fn volward_index_version(engine: *mut VolwardEngine) -> u64 {
    engine_ref(engine).map(|e| e.index_version()).unwrap_or(0)
}
