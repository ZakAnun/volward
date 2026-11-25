use std::os::raw::c_char;
use std::ptr;

use super::{cstr_to_string, engine_ref, to_c_string};
use crate::VolwardEngine;

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
