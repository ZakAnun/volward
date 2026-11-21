use std::os::raw::c_char;
use std::ptr;

use super::{cstr_to_string, engine_ref, to_c_string};
use crate::VolwardEngine;

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
pub unsafe extern "C" fn volward_analyze_capability_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    capability: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let Some(snapshot_id) = cstr_to_string(snapshot_id) else {
        return ptr::null_mut();
    };
    let Some(capability) = cstr_to_string(capability) else {
        return ptr::null_mut();
    };
    let Some(options_json) = cstr_to_string(options_json) else {
        return ptr::null_mut();
    };
    to_c_string(e.analyze_capability_json(&snapshot_id, &capability, &options_json))
}

#[no_mangle]
pub unsafe extern "C" fn volward_start_capability_analysis_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    capability: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let Some(snapshot_id) = cstr_to_string(snapshot_id) else {
        return ptr::null_mut();
    };
    let Some(capability) = cstr_to_string(capability) else {
        return ptr::null_mut();
    };
    let Some(options_json) = cstr_to_string(options_json) else {
        return ptr::null_mut();
    };
    to_c_string(e.start_capability_analysis_json(&snapshot_id, &capability, &options_json))
}

#[no_mangle]
pub unsafe extern "C" fn volward_get_capability_job_status_json(
    engine: *mut VolwardEngine,
    job_id: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let Some(job_id) = cstr_to_string(job_id) else {
        return ptr::null_mut();
    };
    to_c_string(e.get_capability_job_status_json(&job_id))
}

#[no_mangle]
pub unsafe extern "C" fn volward_cancel_capability_analysis(
    engine: *mut VolwardEngine,
    job_id: *const c_char,
) -> bool {
    let Some(e) = engine_ref(engine) else {
        return false;
    };
    let Some(job_id) = cstr_to_string(job_id) else {
        return false;
    };
    e.cancel_capability_analysis(&job_id)
}
