use std::os::raw::c_char;
use std::ptr;

use super::{cstr_to_string, engine_ref, to_c_string};
use crate::VolwardEngine;

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_snapshot_json(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    e.get_last_snapshot_json()
        .map(to_c_string)
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
