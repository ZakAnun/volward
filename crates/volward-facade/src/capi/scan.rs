use std::os::raw::c_char;
use std::ptr;

use super::{cstr_to_string, engine_ref, to_c_string};
use crate::VolwardEngine;
use volward_core::pause_store::FilePauseStore;

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
pub unsafe extern "C" fn volward_request_scan_pause(
    engine: *mut VolwardEngine,
    root: *const c_char,
    cache_dir: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return to_c_string("error:null engine".to_string());
    };
    let Some(root) = cstr_to_string(root) else {
        return to_c_string("error:null root".to_string());
    };
    let Some(cache_dir) = cstr_to_string(cache_dir) else {
        return to_c_string("error:null cache dir".to_string());
    };
    e.pause_current_scan();
    let path =
        FilePauseStore::new(std::path::PathBuf::from(cache_dir).join("pauses")).index_path(&root);
    to_c_string(path.to_string_lossy().into_owned())
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_pause_error(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    e.get_last_pause_error()
        .map(to_c_string)
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_last_progress_json(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    e.get_last_progress_json()
        .map(to_c_string)
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn volward_open_permission_settings(engine: *mut VolwardEngine) -> bool {
    engine_ref(engine)
        .map(|e| e.open_permission_settings().is_ok())
        .unwrap_or(false)
}
