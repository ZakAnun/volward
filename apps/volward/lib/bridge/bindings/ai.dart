import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef VolwardAiBuildCandidatesJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiBuildCandidatesJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiStartBuildCandidatesAsyncNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiStartBuildCandidatesAsync = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiIsCandidatesBuildingNative = Bool Function(Pointer<Void>);
typedef VolwardAiIsCandidatesBuilding = bool Function(Pointer<Void>);
typedef VolwardAiGetCandidatesJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardAiGetCandidatesJson = Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardAiTakeCandidatesSpillPathNative = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardAiTakeCandidatesSpillPath = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardAiSaveResultJsonNative = Bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiSaveResultJson = bool Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiLoadResultJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiLoadResultJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiUpstreamEndpointNative = Pointer<Utf8> Function();
typedef VolwardAiUpstreamEndpoint = Pointer<Utf8> Function();
typedef VolwardAiBatchSizeNative = Uint32 Function();
typedef VolwardAiBatchSize = int Function();
typedef VolwardAiBuildRequestJsonNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef VolwardAiBuildRequestJson = Pointer<Utf8> Function(Pointer<Utf8>);
typedef VolwardAiBuildConclusionSynthesisJsonNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
);
typedef VolwardAiBuildConclusionSynthesisJson = Pointer<Utf8> Function(
  Pointer<Utf8>,
);
typedef VolwardAiParseResponseJsonNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiParseResponseJson = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiTreeBatchSizeNative = Uint32 Function();
typedef VolwardAiTreeBatchSize = int Function();
typedef VolwardAiBuildTreeRequestJsonNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
);
typedef VolwardAiBuildTreeRequestJson = Pointer<Utf8> Function(Pointer<Utf8>);
typedef VolwardAiParseTreeResponseJsonNative = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiParseTreeResponseJson = Pointer<Utf8> Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiBuildCoveragePlanJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiBuildCoveragePlanJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiStartBuildCoveragePlanAsyncNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Bool,
);
typedef VolwardAiStartBuildCoveragePlanAsync = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  bool,
);
typedef VolwardAiIsCoveragePlanBuildingNative = Bool Function(Pointer<Void>);
typedef VolwardAiIsCoveragePlanBuilding = bool Function(Pointer<Void>);
typedef VolwardAiGetCoveragePlanJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
);
typedef VolwardAiGetCoveragePlanJson = Pointer<Utf8> Function(Pointer<Void>);
typedef VolwardAiNextCoveragePageJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Uint64,
  Uint64,
  Uint32,
);
typedef VolwardAiNextCoveragePageJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  int,
  int,
);
typedef VolwardAiListLocalCoverageVerdictsJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Uint64,
  Uint32,
);
typedef VolwardAiListLocalCoverageVerdictsJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  int,
);
typedef VolwardAiResolveCoverageGroupJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiResolveCoverageGroupJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiBuildTreeCoveragePlanJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiBuildTreeCoveragePlanJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef VolwardAiNextTreeCoveragePageJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Uint64,
  Uint64,
  Uint32,
);
typedef VolwardAiNextTreeCoveragePageJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  int,
  int,
);
typedef VolwardAiNextTailCoveragePageJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Uint64,
  Uint64,
  Uint32,
);
typedef VolwardAiNextTailCoveragePageJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
  int,
  int,
);
typedef VolwardAiExpandTreeNodeJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiExpandTreeNodeJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiApplyDirVerdictJsonNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiApplyDirVerdictJson = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiApplyDirVerdictToFileNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
typedef VolwardAiApplyDirVerdictToFile = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);
