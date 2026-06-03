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
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let job = cstr_to_string(job_id).unwrap_or_else(|| "flutter-job".to_string());
    let roots: Vec<String> = cstr_to_string(roots_json)
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    to_c_string(e.start_scan(job, roots))
}

#[no_mangle]
pub unsafe extern "C" fn volward_start_scan_async(
    engine: *mut VolwardEngine,
    job_id: *const c_char,
    roots_json: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let job = cstr_to_string(job_id).unwrap_or_else(|| "flutter-job".to_string());
    let roots: Vec<String> = cstr_to_string(roots_json)
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    to_c_string(e.start_scan_async(job, roots))
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
pub unsafe extern "C" fn volward_get_last_snapshot_json(
    engine: *mut VolwardEngine,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    e.get_last_snapshot_json()
        .map(|s| to_c_string(s))
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_progress_json(
    engine: *mut VolwardEngine,
) -> *mut c_char {
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

unsafe fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string())
}
