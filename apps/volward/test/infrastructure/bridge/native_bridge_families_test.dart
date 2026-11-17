import 'dart:io';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/bridge/native_bridge.dart';
import 'package:volward/infrastructure/bridge/ai_bridge.dart';
import 'package:volward/infrastructure/bridge/capability_bridge.dart';
import 'package:volward/infrastructure/bridge/delete_bridge.dart';
import 'package:volward/infrastructure/bridge/engine_bridge.dart';
import 'package:volward/infrastructure/bridge/index_bridge.dart';
import 'package:volward/infrastructure/bridge/runtime/native_library.dart';
import 'package:volward/infrastructure/bridge/runtime/native_string.dart';
import 'package:volward/infrastructure/bridge/scan_bridge.dart';

void main() {
  final originalDebugPrint = debugPrint;
  setUpAll(() => debugPrint = (_, {int? wrapWidth}) {});
  tearDownAll(() => debugPrint = originalDebugPrint);

  group('NativeLibraryHandle family construction', () {
    test('optional scan and index symbols gate capability booleans', () {
      final handle = _FakeNativeLibraryHandle(
        missingSymbols: {
          'volward_start_scan_async_with_options',
          'volward_quick_list_dir_json',
          'volward_write_last_snapshot_to_path',
          'volward_load_last_snapshot_from_path',
          'volward_write_last_checkpoint_to_path',
          'volward_write_last_snapshot_to_path_pb',
          'volward_write_last_checkpoint_to_path_pb',
          'volward_query_directory_json',
          'volward_refresh_directory',
          'volward_load_index_from_path',
          'volward_start_load_index_from_path_async',
          'volward_is_index_loading',
          'volward_invalidate_index_load',
          'volward_get_last_index_load_error',
          'volward_write_last_index_to_path',
          'volward_get_index_summary_json',
          'volward_index_version',
          'volward_replace_directory_with_subtree',
          'volward_empty_trash_json',
          'volward_analyze_capability_json',
          'volward_start_capability_analysis_json',
          'volward_get_capability_job_status_json',
          'volward_cancel_capability_analysis',
          'volward_ai_build_candidates_json',
          'volward_ai_start_build_candidates_async',
          'volward_ai_is_candidates_building',
          'volward_ai_get_candidates_json',
          'volward_ai_take_candidates_spill_path',
          'volward_ai_save_result_json',
          'volward_ai_load_result_json',
          'volward_ai_upstream_endpoint',
          'volward_ai_batch_size',
          'volward_ai_build_request_json',
          'volward_ai_build_conclusion_synthesis_json',
          'volward_ai_parse_response_json',
          'volward_ai_tree_batch_size',
          'volward_ai_build_tree_request_json',
          'volward_ai_parse_tree_response_json',
          'volward_ai_build_coverage_plan_json',
          'volward_ai_start_build_coverage_plan_async',
          'volward_ai_is_coverage_plan_building',
          'volward_ai_get_coverage_plan_json',
          'volward_ai_next_coverage_page_json',
          'volward_ai_list_local_coverage_verdicts_json',
          'volward_ai_resolve_coverage_group_json',
          'volward_ai_build_tree_coverage_plan_json',
          'volward_ai_next_tree_coverage_page_json',
          'volward_ai_next_tail_coverage_page_json',
          'volward_ai_expand_tree_node_json',
          'volward_ai_apply_dir_verdict_json',
          'volward_ai_apply_dir_verdict_to_file',
        },
      );
      final codec = NativeStringCodec((_) {});

      final scan = ScanNativeBridge(handle, codec);
      final index = IndexNativeBridge(handle, codec);
      final delete = DeleteNativeBridge(handle, codec);
      final capability = CapabilityNativeBridge(handle, codec);
      final ai = AiNativeBridge(handle, codec);

      expect(scan.hasScanOptionsApi, isFalse);
      expect(scan.hasQuickListApi, isFalse);
      expect(index.hasIndexApi, isFalse);
      expect(index.hasAsyncIndexLoadApi, isFalse);
      expect(capability.hasCapabilityApi, isFalse);
      expect(ai.hasAiCoverageApi, isFalse);
      expect(ai.hasAiTreeCoverageApi, isFalse);
      expect(ai.hasAiSessionApi, isFalse);
      expect(ai.hasAiContractApi, isFalse);
      expect(ai.hasAiTreeContractApi, isFalse);
      expect(delete.emptyTrash(Pointer<Void>.fromAddress(1)), const {
        'error': 'native dylib missing volward_empty_trash_json — rebuild Rust',
      });
      expect(handle.requiredLookups, contains('volward_start_scan'));
      expect(
        handle.requiredLookups,
        contains('volward_get_last_snapshot_json'),
      );
      expect(
        handle.optionalLookups,
        contains('volward_start_scan_async_with_options'),
      );
      expect(handle.optionalLookups, contains('volward_query_directory_json'));
    });
  });

  group('Concrete family call paths', () {
    test('delete, capability, and AI success paths decode native results', () {
      final emptyTrashCallable =
          NativeCallable<Pointer<Utf8> Function(Pointer<Void>)>.isolateLocal(
            _emptyTrashSuccessResult,
          );
      final statusCallable =
          NativeCallable<
            Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)
          >.isolateLocal(_capabilityStatusSuccessResult);
      final parseCallable =
          NativeCallable<
            Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)
          >.isolateLocal(_aiParseSuccessResult);
      addTearDown(emptyTrashCallable.close);
      addTearDown(statusCallable.close);
      addTearDown(parseCallable.close);

      final handle = _CallableNativeLibraryHandle({
        'volward_empty_trash_json': emptyTrashCallable.nativeFunction,
        'volward_get_capability_job_status_json': statusCallable.nativeFunction,
        'volward_ai_parse_response_json': parseCallable.nativeFunction,
      });
      final codec = NativeStringCodec(malloc.free);
      final engine = Pointer<Void>.fromAddress(1);

      expect(DeleteNativeBridge(handle, codec).emptyTrash(engine), {
        'deleted': 1,
      });
      expect(
        CapabilityNativeBridge(
          handle,
          codec,
        ).getCapabilityJobStatus(engine, 'job'),
        '{"progress":1}',
      );
      expect(
        AiNativeBridge(handle, codec).aiParseResponseJson('{}', '[]'),
        '[{"verdict":"keep"}]',
      );
    });

    test(
      'nullable capability and AI results preserve their fallback paths',
      () {
        final nullStatusCallable =
            NativeCallable<
              Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)
            >.isolateLocal(_nullCapabilityStatusResult);
        final nullParseCallable =
            NativeCallable<
              Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>)
            >.isolateLocal(_nullAiParseResult);
        addTearDown(nullStatusCallable.close);
        addTearDown(nullParseCallable.close);

        final handle = _CallableNativeLibraryHandle({
          'volward_get_capability_job_status_json':
              nullStatusCallable.nativeFunction,
          'volward_ai_parse_response_json': nullParseCallable.nativeFunction,
        });
        final codec = NativeStringCodec(malloc.free);
        final engine = Pointer<Void>.fromAddress(1);

        expect(
          CapabilityNativeBridge(
            handle,
            codec,
          ).getCapabilityJobStatus(engine, 'job'),
          'error:null capability status',
        );
        expect(
          AiNativeBridge(handle, codec).aiParseResponseJson('{}', '[]'),
          isNull,
        );
      },
    );
  });

  group('VolwardNativeBridge family delegation', () {
    test(
      'facade delegates scan calls without changing the native contract',
      () {
        final engine = Pointer<Void>.fromAddress(1);
        final scan = _FakeScanBridge();
        final bridge = VolwardNativeBridge.test(scan: scan);

        expect(bridge.startScan(engine, 'job-1', ['/tmp']), 'job-1');
        expect(scan.startCalls, 1);
      },
    );

    test('facade delegates engine lifecycle calls', () {
      final engineBridge = _FakeEngineBridge();
      final bridge = VolwardNativeBridge.test(engine: engineBridge);
      final engine = bridge.createEngine();

      bridge.freeEngine(engine);

      expect(engineBridge.createCalls, 1);
      expect(engineBridge.freedEngines, [engine]);
    });

    test('facade delegates index query calls', () {
      final index = _FakeIndexBridge();
      final bridge = VolwardNativeBridge.test(index: index);

      expect(
        bridge.queryDirectoryJson(
          Pointer<Void>.fromAddress(1),
          '/tmp',
          categoryFilter: 'Cache',
          deletableOnly: true,
          sortMode: 'name_asc',
        ),
        {'children': <dynamic>[]},
      );
      expect(index.queryCalls, 1);
    });

    test('facade delegates delete, capability, and AI calls', () {
      final engine = Pointer<Void>.fromAddress(1);
      final delete = _FakeDeleteBridge();
      final capability = _FakeCapabilityBridge();
      final ai = _FakeAiBridge();
      final bridge = VolwardNativeBridge.test(
        delete: delete,
        capability: capability,
        ai: ai,
      );

      expect(bridge.deleteEntries(engine, 'snap', ['a']), {'deleted': 1});
      expect(bridge.emptyTrash(engine), {'deleted': 2});
      expect(bridge.getCapabilityJobStatus(engine, 'job'), '{"progress":1}');
      expect(bridge.aiParseResponseJson('{}', '[]'), 'error:null response');
      expect(bridge.hasAiCoverageApi, isFalse);
      expect(delete.calls, 2);
      expect(capability.statusCalls, 1);
      expect(ai.parseCalls, 1);
    });
  });

  group('bridge file responsibilities', () {
    test('compatibility facade and families stay within file budgets', () {
      int lineCount(String path) => File(path).readAsLinesSync().length;

      expect(lineCount('lib/bridge/native_bridge.dart'), lessThan(300));
      expect(
        lineCount('lib/infrastructure/bridge/delete_bridge.dart'),
        lessThan(800),
      );
      expect(
        lineCount('lib/infrastructure/bridge/capability_bridge.dart'),
        lessThan(800),
      );
      expect(
        lineCount('lib/infrastructure/bridge/ai_bridge.dart'),
        lessThan(800),
      );
    });
  });

  group('NativeStringCodec', () {
    test('scan-owned return strings are freed exactly once', () {
      final pointer = '{"phase":"Done"}'.toNativeUtf8();
      var freeCalls = 0;
      final codec = NativeStringCodec((value) {
        freeCalls++;
        calloc.free(value);
      });

      expect(codec.decodeAndFree(pointer), contains('Done'));
      expect(freeCalls, 1);
    });

    test('nullable return strings preserve null without freeing', () {
      var freeCalls = 0;
      final codec = NativeStringCodec((value) {
        freeCalls++;
        calloc.free(value);
      });

      expect(codec.decodeAndFreeNullable(nullptr), isNull);
      expect(freeCalls, 0);
    });
  });
}

class _FakeEngineBridge implements EngineBridge {
  int createCalls = 0;
  final List<Pointer<Void>> freedEngines = [];

  @override
  NativeStringCodec get codec => NativeStringCodec((_) {});

  @override
  Pointer<Void> createEngine() {
    createCalls++;
    return Pointer<Void>.fromAddress(42);
  }

  @override
  void freeEngine(Pointer<Void> engine) {
    freedEngines.add(engine);
  }

  @override
  void freeString(Pointer<Utf8> value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNativeLibraryHandle implements NativeLibraryHandle {
  _FakeNativeLibraryHandle({required this._missingSymbols});

  final Set<String> _missingSymbols;
  final Set<String> requiredLookups = {};
  final Set<String> optionalLookups = {};
  late final Pointer<NativeFunction<Int32 Function()>> _nonNullFunction =
      DynamicLibrary.process().lookup<NativeFunction<Int32 Function()>>(
        'getpid',
      );

  @override
  Pointer<T> lookup<T extends NativeFunction>(String symbol) {
    requiredLookups.add(symbol);
    if (_missingSymbols.contains(symbol)) {
      throw ArgumentError.value(symbol, 'symbol', 'required symbol is absent');
    }
    return _nonNullFunction.cast<T>();
  }

  @override
  Pointer<T>? tryLookup<T extends NativeFunction>(String symbol) {
    optionalLookups.add(symbol);
    if (_missingSymbols.contains(symbol)) return null;
    return lookup<T>(symbol);
  }
}

class _CallableNativeLibraryHandle implements NativeLibraryHandle {
  _CallableNativeLibraryHandle(this._symbols);

  final Map<String, Pointer<NativeFunction>> _symbols;
  late final Pointer<NativeFunction<Int32 Function()>> _fallback =
      DynamicLibrary.process().lookup<NativeFunction<Int32 Function()>>(
        'getpid',
      );

  @override
  Pointer<T> lookup<T extends NativeFunction>(String symbol) =>
      (_symbols[symbol] ?? _fallback).cast<T>();

  @override
  Pointer<T>? tryLookup<T extends NativeFunction>(String symbol) {
    final value = _symbols[symbol];
    return value?.cast<T>();
  }
}

Pointer<Utf8> _emptyTrashSuccessResult(Pointer<Void> engine) =>
    '{"deleted":1}'.toNativeUtf8();

Pointer<Utf8> _capabilityStatusSuccessResult(
  Pointer<Void> engine,
  Pointer<Utf8> jobId,
) => '{"progress":1}'.toNativeUtf8();

Pointer<Utf8> _aiParseSuccessResult(
  Pointer<Utf8> upstreamBody,
  Pointer<Utf8> batchJson,
) => '[{"verdict":"keep"}]'.toNativeUtf8();

Pointer<Utf8> _nullCapabilityStatusResult(
  Pointer<Void> engine,
  Pointer<Utf8> jobId,
) => nullptr;

Pointer<Utf8> _nullAiParseResult(
  Pointer<Utf8> upstreamBody,
  Pointer<Utf8> batchJson,
) => nullptr;

class _FakeScanBridge implements ScanBridge {
  int startCalls = 0;

  @override
  bool get hasScanOptionsApi => false;

  @override
  bool get hasQuickListApi => false;

  @override
  String startScan(Pointer<Void> engine, String jobId, List<String> roots) {
    startCalls++;
    return jobId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIndexBridge implements IndexBridge {
  int queryCalls = 0;

  @override
  Map<String, dynamic> queryDirectoryJson(
    Pointer<Void> engine,
    String path, {
    String? categoryFilter,
    bool deletableOnly = false,
    String sortMode = 'size_desc',
  }) {
    queryCalls++;
    return {'children': <dynamic>[]};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeleteBridge implements DeleteBridge {
  int calls = 0;

  @override
  Map<String, dynamic> deleteEntries(
    Pointer<Void> engine,
    String snapshotId,
    List<String> entryIds, {
    bool dryRun = false,
  }) {
    calls++;
    return {'deleted': entryIds.length};
  }

  @override
  Map<String, dynamic> emptyTrash(Pointer<Void> engine) {
    calls++;
    return {'deleted': 2};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCapabilityBridge implements CapabilityBridge {
  int statusCalls = 0;

  @override
  bool get hasCapabilityApi => true;

  @override
  String getCapabilityJobStatus(Pointer<Void> engine, String jobId) {
    statusCalls++;
    return '{"progress":1}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAiBridge implements AiBridge {
  int parseCalls = 0;

  @override
  bool get hasAiCoverageApi => false;

  @override
  bool get hasAiTreeCoverageApi => false;

  @override
  bool get hasAiSessionApi => false;

  @override
  bool get hasAiContractApi => false;

  @override
  bool get hasAiTreeContractApi => false;

  @override
  bool get hasAsyncAiCandidatesApi => false;

  @override
  bool get hasAsyncAiCoveragePlanApi => false;

  @override
  bool get hasApplyDirVerdictToFileApi => false;

  @override
  String? aiParseResponseJson(String upstreamBody, String batchJson) {
    parseCalls++;
    return 'error:null response';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
