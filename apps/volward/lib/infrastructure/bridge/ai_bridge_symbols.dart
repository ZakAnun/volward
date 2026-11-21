import 'dart:ffi';

import '../../bridge/bindings/ai.dart';
import 'runtime/native_library.dart';

class AiNativeSymbols {
  AiNativeSymbols(NativeLibraryHandle library)
    : buildCandidatesJson = library
          .tryLookup<NativeFunction<VolwardAiBuildCandidatesJsonNative>>(
            'volward_ai_build_candidates_json',
          )
          ?.asFunction(),
      startBuildCandidatesAsync = library
          .tryLookup<NativeFunction<VolwardAiStartBuildCandidatesAsyncNative>>(
            'volward_ai_start_build_candidates_async',
          )
          ?.asFunction(),
      isCandidatesBuilding = library
          .tryLookup<NativeFunction<VolwardAiIsCandidatesBuildingNative>>(
            'volward_ai_is_candidates_building',
          )
          ?.asFunction(),
      getCandidatesJson = library
          .tryLookup<NativeFunction<VolwardAiGetCandidatesJsonNative>>(
            'volward_ai_get_candidates_json',
          )
          ?.asFunction(),
      takeCandidatesSpillPath = library
          .tryLookup<NativeFunction<VolwardAiTakeCandidatesSpillPathNative>>(
            'volward_ai_take_candidates_spill_path',
          )
          ?.asFunction(),
      saveResultJson = library
          .tryLookup<NativeFunction<VolwardAiSaveResultJsonNative>>(
            'volward_ai_save_result_json',
          )
          ?.asFunction(),
      loadResultJson = library
          .tryLookup<NativeFunction<VolwardAiLoadResultJsonNative>>(
            'volward_ai_load_result_json',
          )
          ?.asFunction(),
      upstreamEndpoint = library
          .tryLookup<NativeFunction<VolwardAiUpstreamEndpointNative>>(
            'volward_ai_upstream_endpoint',
          )
          ?.asFunction(),
      batchSize = library
          .tryLookup<NativeFunction<VolwardAiBatchSizeNative>>(
            'volward_ai_batch_size',
          )
          ?.asFunction(),
      buildRequestJson = library
          .tryLookup<NativeFunction<VolwardAiBuildRequestJsonNative>>(
            'volward_ai_build_request_json',
          )
          ?.asFunction(),
      buildConclusionSynthesisJson = library
          .tryLookup<
            NativeFunction<VolwardAiBuildConclusionSynthesisJsonNative>
          >('volward_ai_build_conclusion_synthesis_json')
          ?.asFunction(),
      parseResponseJson = library
          .tryLookup<NativeFunction<VolwardAiParseResponseJsonNative>>(
            'volward_ai_parse_response_json',
          )
          ?.asFunction(),
      treeBatchSize = library
          .tryLookup<NativeFunction<VolwardAiTreeBatchSizeNative>>(
            'volward_ai_tree_batch_size',
          )
          ?.asFunction(),
      buildTreeRequestJson = library
          .tryLookup<NativeFunction<VolwardAiBuildTreeRequestJsonNative>>(
            'volward_ai_build_tree_request_json',
          )
          ?.asFunction(),
      parseTreeResponseJson = library
          .tryLookup<NativeFunction<VolwardAiParseTreeResponseJsonNative>>(
            'volward_ai_parse_tree_response_json',
          )
          ?.asFunction(),
      buildCoveragePlanJson = library
          .tryLookup<NativeFunction<VolwardAiBuildCoveragePlanJsonNative>>(
            'volward_ai_build_coverage_plan_json',
          )
          ?.asFunction(),
      startBuildCoveragePlanAsync = library
          .tryLookup<
            NativeFunction<VolwardAiStartBuildCoveragePlanAsyncNative>
          >('volward_ai_start_build_coverage_plan_async')
          ?.asFunction(),
      isCoveragePlanBuilding = library
          .tryLookup<NativeFunction<VolwardAiIsCoveragePlanBuildingNative>>(
            'volward_ai_is_coverage_plan_building',
          )
          ?.asFunction(),
      getCoveragePlanJson = library
          .tryLookup<NativeFunction<VolwardAiGetCoveragePlanJsonNative>>(
            'volward_ai_get_coverage_plan_json',
          )
          ?.asFunction(),
      nextCoveragePageJson = library
          .tryLookup<NativeFunction<VolwardAiNextCoveragePageJsonNative>>(
            'volward_ai_next_coverage_page_json',
          )
          ?.asFunction(),
      listLocalCoverageVerdictsJson = library
          .tryLookup<
            NativeFunction<VolwardAiListLocalCoverageVerdictsJsonNative>
          >('volward_ai_list_local_coverage_verdicts_json')
          ?.asFunction(),
      resolveCoverageGroupJson = library
          .tryLookup<NativeFunction<VolwardAiResolveCoverageGroupJsonNative>>(
            'volward_ai_resolve_coverage_group_json',
          )
          ?.asFunction(),
      buildTreeCoveragePlanJson = library
          .tryLookup<NativeFunction<VolwardAiBuildTreeCoveragePlanJsonNative>>(
            'volward_ai_build_tree_coverage_plan_json',
          )
          ?.asFunction(),
      nextTreeCoveragePageJson = library
          .tryLookup<NativeFunction<VolwardAiNextTreeCoveragePageJsonNative>>(
            'volward_ai_next_tree_coverage_page_json',
          )
          ?.asFunction(),
      nextTailCoveragePageJson = library
          .tryLookup<NativeFunction<VolwardAiNextTailCoveragePageJsonNative>>(
            'volward_ai_next_tail_coverage_page_json',
          )
          ?.asFunction(),
      expandTreeNodeJson = library
          .tryLookup<NativeFunction<VolwardAiExpandTreeNodeJsonNative>>(
            'volward_ai_expand_tree_node_json',
          )
          ?.asFunction(),
      applyDirVerdictJson = library
          .tryLookup<NativeFunction<VolwardAiApplyDirVerdictJsonNative>>(
            'volward_ai_apply_dir_verdict_json',
          )
          ?.asFunction(),
      applyDirVerdictToFile = library
          .tryLookup<NativeFunction<VolwardAiApplyDirVerdictToFileNative>>(
            'volward_ai_apply_dir_verdict_to_file',
          )
          ?.asFunction();

  final VolwardAiBuildCandidatesJson? buildCandidatesJson;
  final VolwardAiStartBuildCandidatesAsync? startBuildCandidatesAsync;
  final VolwardAiIsCandidatesBuilding? isCandidatesBuilding;
  final VolwardAiGetCandidatesJson? getCandidatesJson;
  final VolwardAiTakeCandidatesSpillPath? takeCandidatesSpillPath;
  final VolwardAiSaveResultJson? saveResultJson;
  final VolwardAiLoadResultJson? loadResultJson;
  final VolwardAiUpstreamEndpoint? upstreamEndpoint;
  final VolwardAiBatchSize? batchSize;
  final VolwardAiBuildRequestJson? buildRequestJson;
  final VolwardAiBuildConclusionSynthesisJson? buildConclusionSynthesisJson;
  final VolwardAiParseResponseJson? parseResponseJson;
  final VolwardAiTreeBatchSize? treeBatchSize;
  final VolwardAiBuildTreeRequestJson? buildTreeRequestJson;
  final VolwardAiParseTreeResponseJson? parseTreeResponseJson;
  final VolwardAiBuildCoveragePlanJson? buildCoveragePlanJson;
  final VolwardAiStartBuildCoveragePlanAsync? startBuildCoveragePlanAsync;
  final VolwardAiIsCoveragePlanBuilding? isCoveragePlanBuilding;
  final VolwardAiGetCoveragePlanJson? getCoveragePlanJson;
  final VolwardAiNextCoveragePageJson? nextCoveragePageJson;
  final VolwardAiListLocalCoverageVerdictsJson? listLocalCoverageVerdictsJson;
  final VolwardAiResolveCoverageGroupJson? resolveCoverageGroupJson;
  final VolwardAiBuildTreeCoveragePlanJson? buildTreeCoveragePlanJson;
  final VolwardAiNextTreeCoveragePageJson? nextTreeCoveragePageJson;
  final VolwardAiNextTailCoveragePageJson? nextTailCoveragePageJson;
  final VolwardAiExpandTreeNodeJson? expandTreeNodeJson;
  final VolwardAiApplyDirVerdictJson? applyDirVerdictJson;
  final VolwardAiApplyDirVerdictToFile? applyDirVerdictToFile;
}
