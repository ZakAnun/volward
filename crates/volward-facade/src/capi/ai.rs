use std::os::raw::c_char;
use std::ptr;

use super::{cstr_to_string, engine_ref, to_c_string};
use crate::VolwardEngine;

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
pub unsafe extern "C" fn volward_ai_get_candidates_json(engine: *mut VolwardEngine) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    to_c_string(e.get_ai_candidates_json())
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_take_candidates_spill_path(
    engine: *mut VolwardEngine,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    to_c_string(e.take_ai_candidates_spill_path())
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_start_build_coverage_plan_async(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    tree: bool,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.start_build_ai_coverage_plan_async(snapshot_id, tree))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_is_coverage_plan_building(engine: *mut VolwardEngine) -> bool {
    let Some(e) = engine_ref(engine) else {
        return false;
    };
    e.is_ai_coverage_plan_building()
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_get_coverage_plan_json(
    engine: *mut VolwardEngine,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    to_c_string(e.get_ai_coverage_plan_json())
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_build_coverage_plan_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.build_ai_coverage_plan_json(&snapshot_id))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_list_local_coverage_verdicts_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    cursor: u64,
    limit: u32,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.list_local_coverage_verdicts_json(&snapshot_id, cursor, limit))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_next_coverage_page_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    plan_version: u64,
    cursor: u64,
    page_size: u32,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.next_ai_coverage_page_json(&snapshot_id, plan_version, cursor, page_size))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_build_tree_coverage_plan_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.build_ai_tree_plan_json(&snapshot_id))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_next_tree_coverage_page_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    plan_version: u64,
    cursor: u64,
    page_size: u32,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.next_ai_tree_coverage_page_json(
        &snapshot_id,
        plan_version,
        cursor,
        page_size,
    ))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_next_tail_coverage_page_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    plan_version: u64,
    cursor: u64,
    page_size: u32,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.next_ai_tail_coverage_page_json(
        &snapshot_id,
        plan_version,
        cursor,
        page_size,
    ))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_next_scope_coverage_page_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    plan_version: u64,
    cursor: u64,
    page_size: u32,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    to_c_string(e.next_ai_scope_coverage_page_json(
        &snapshot_id,
        plan_version,
        cursor,
        page_size,
    ))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_expand_tree_node_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    dir_path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    let dir_path = cstr_to_string(dir_path).unwrap_or_default();
    to_c_string(e.expand_ai_tree_node_json(&snapshot_id, &dir_path))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_apply_dir_verdict_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    dir_path: *const c_char,
    verdict: *const c_char,
    confidence: *const c_char,
    role_snake_case: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    let dir_path = cstr_to_string(dir_path).unwrap_or_default();
    let verdict = cstr_to_string(verdict).unwrap_or_default();
    let confidence = cstr_to_string(confidence).unwrap_or_default();
    let role_snake_case = cstr_to_string(role_snake_case).unwrap_or_default();
    to_c_string(e.apply_ai_dir_verdict_json(
        &snapshot_id,
        &dir_path,
        &verdict,
        &confidence,
        &role_snake_case,
    ))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_apply_dir_verdict_to_file(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    dir_path: *const c_char,
    verdict: *const c_char,
    confidence: *const c_char,
    role_snake_case: *const c_char,
    out_path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    let dir_path = cstr_to_string(dir_path).unwrap_or_default();
    let verdict = cstr_to_string(verdict).unwrap_or_default();
    let confidence = cstr_to_string(confidence).unwrap_or_default();
    let role_snake_case = cstr_to_string(role_snake_case).unwrap_or_default();
    let out_path = cstr_to_string(out_path).unwrap_or_default();
    to_c_string(e.apply_ai_dir_verdict_to_file(
        &snapshot_id,
        &dir_path,
        &verdict,
        &confidence,
        &role_snake_case,
        &out_path,
    ))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_resolve_coverage_group_json(
    engine: *mut VolwardEngine,
    snapshot_id: *const c_char,
    group_path: *const c_char,
) -> *mut c_char {
    let Some(e) = engine_ref(engine) else {
        return ptr::null_mut();
    };
    let snapshot_id = cstr_to_string(snapshot_id).unwrap_or_default();
    let group_path = cstr_to_string(group_path).unwrap_or_default();
    to_c_string(e.resolve_ai_coverage_group_json(&snapshot_id, &group_path))
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
pub unsafe extern "C" fn volward_ai_upstream_endpoint() -> *mut c_char {
    to_c_string(volward_ai::UPSTREAM_ENDPOINT.to_string())
}

/// Batch size is a contract value — Dart must read it here, never hardcode 40.
#[no_mangle]
pub unsafe extern "C" fn volward_ai_batch_size() -> u32 {
    volward_ai::BATCH_SIZE as u32
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_tree_batch_size() -> u32 {
    volward_ai::TREE_BATCH_SIZE as u32
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_build_tree_request_json(
    nodes_json: *const c_char,
) -> *mut c_char {
    let Some(raw) = cstr_to_string(nodes_json) else {
        return to_c_string("error:null nodes".into());
    };
    match serde_json::from_str::<Vec<volward_ai::AnalyzeTreeNode>>(&raw) {
        Ok(nodes) => to_c_string(volward_ai::build_tree_request_body(&nodes)),
        Err(e) => to_c_string(format!("error:parse:{e}")),
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_parse_tree_response_json(
    response_json: *const c_char,
    batch_json: *const c_char,
) -> *mut c_char {
    let Some(body) = cstr_to_string(response_json) else {
        return to_c_string("error:null response".into());
    };
    let Some(raw_batch) = cstr_to_string(batch_json) else {
        return to_c_string("error:null batch".into());
    };
    let batch: Vec<volward_ai::AnalyzeTreeNode> = match serde_json::from_str(&raw_batch) {
        Ok(b) => b,
        Err(e) => return to_c_string(format!("error:parse:{e}")),
    };
    let verdicts = volward_ai::parse_tree_response(&body, &batch);
    match serde_json::to_string(&verdicts) {
        Ok(s) => to_c_string(s),
        Err(e) => to_c_string(format!("error:encode:{e}")),
    }
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_build_request_json(
    candidates_json: *const c_char,
) -> *mut c_char {
    let Some(raw) = cstr_to_string(candidates_json) else {
        return to_c_string("error:null candidates".into());
    };
    match serde_json::from_str::<Vec<volward_ai::AnalyzeCandidate>>(&raw) {
        Ok(c) => to_c_string(volward_ai::build_request_body(&c)),
        Err(e) => to_c_string(format!("error:parse:{e}")),
    }
}

/// Build DeepSeek request JSON for conclusion synthesis (Stage B user JSON in, chat body out).
#[no_mangle]
pub unsafe extern "C" fn volward_ai_build_conclusion_synthesis_json(
    user_json: *const c_char,
) -> *mut c_char {
    let Some(raw) = cstr_to_string(user_json) else {
        return to_c_string("error:null user_json".into());
    };
    to_c_string(volward_ai::build_conclusion_synthesis_body(&raw))
}

#[no_mangle]
pub unsafe extern "C" fn volward_ai_parse_response_json(
    response_json: *const c_char,
    batch_json: *const c_char,
) -> *mut c_char {
    let Some(body) = cstr_to_string(response_json) else {
        return to_c_string("error:null response".into());
    };
    let Some(raw_batch) = cstr_to_string(batch_json) else {
        return to_c_string("error:null batch".into());
    };
    let batch: Vec<volward_ai::AnalyzeCandidate> = match serde_json::from_str(&raw_batch) {
        Ok(b) => b,
        Err(e) => return to_c_string(format!("error:parse:{e}")),
    };
    let verdicts = volward_ai::parse_response(&body, &batch);
    match serde_json::to_string(&verdicts) {
        Ok(s) => to_c_string(s),
        Err(e) => to_c_string(format!("error:encode:{e}")),
    }
}
