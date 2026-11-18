import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:volward/core/contracts/native_engine_ports.dart';
import 'package:volward/core/session/engine_host.dart';
import 'package:volward/infrastructure/bridge/native_engine_bridge_set.dart';
import 'package:volward/infrastructure/bridge/native_engine_host_backend.dart';
import 'package:volward/infrastructure/bridge/runtime/native_string.dart';

void main() {
  test('engine free waits for every admitted borrower', () {
    final freed = <String>[];
    final host = EngineHost.forTest(
      engine: Pointer<Void>.fromAddress(1),
      freeEngine: () => freed.add('free'),
      backend: NativeEngineHostBackend(
        _bridges(engine: _FakeEngineBridge(onFree: () => freed.add('free'))),
      ),
    );
    final first = host.borrow();
    final second = host.borrow();

    host.dispose();
    expect(freed, isEmpty);

    first.release();
    expect(freed, isEmpty);

    second.release();
    expect(freed, ['free']);
  });

  test('ports reject calls after close', () {
    final host = EngineHost.forTest(
      engine: Pointer<Void>.fromAddress(1),
      backend: NativeEngineHostBackend(_bridges(scan: _FakeScanBridge())),
    );

    host.dispose();

    expect(host.scan.isScanRunning, throwsStateError);
  });

  test('public scan port is pointer-free', () {
    final host = EngineHost.forTest(
      engine: Pointer<Void>.fromAddress(1),
      backend: NativeEngineHostBackend(_bridges(scan: _FakeScanBridge())),
    );

    final ScanEnginePort scan = host.scan;
    final bool Function() isRunning = scan.isScanRunning;
    expect(isRunning(), isFalse);
  });

  test('create owns one engine and exposes probed capabilities', () {
    final engineBridge = _FakeEngineBridge();
    final capability = _FakeCapabilityBridge();
    final host = EngineHost.create(
      backend: NativeEngineHostBackend(
        _bridges(engine: engineBridge, capability: capability),
      ),
    );

    expect(host.ready, isTrue);
    expect(engineBridge.createCalls, 1);
    expect(host.capabilities, const {'index_api': true});
    expect(host.deepScanReady, isTrue);
    expect(capability.probeCalls, 1);

    host.dispose();
    expect(engineBridge.freed, isTrue);
  });

  test('create frees the engine when capability probing throws', () {
    final engineBridge = _FakeEngineBridge();
    final capability = _FakeCapabilityBridge(
      probeError: StateError('capability probe failed'),
    );

    expect(
      () => EngineHost.create(
        backend: NativeEngineHostBackend(
          _bridges(engine: engineBridge, capability: capability),
        ),
      ),
      throwsStateError,
    );
    expect(engineBridge.freed, isTrue);
  });

  test('lifetime forwarding library keeps the original import path', () {
    final host = EngineHost.forTest(
      engine: Pointer<Void>.fromAddress(1),
      freeEngine: () {},
    );
    expect(host.lifetime.isClosed, isFalse);
    host.dispose();
    expect(host.lifetime.isClosed, isTrue);
  });
}

NativeEngineBridgeSet _bridges({
  _FakeEngineBridge? engine,
  _FakeScanBridge? scan,
  _FakeIndexBridge? index,
  _FakeDeleteBridge? delete,
  _FakeCapabilityBridge? capability,
  _FakeAiBridge? ai,
}) => NativeEngineBridgeSet(
  engine: engine ?? _FakeEngineBridge(),
  scan: scan ?? _FakeScanBridge(),
  index: index ?? _FakeIndexBridge(),
  delete: delete ?? _FakeDeleteBridge(),
  capability: capability ?? _FakeCapabilityBridge(),
  ai: ai ?? _FakeAiBridge(),
);

class _FakeEngineBridge implements EngineBridge {
  _FakeEngineBridge({this.onFree});

  final void Function()? onFree;
  int createCalls = 0;
  bool freed = false;

  @override
  NativeStringCodec get codec => NativeStringCodec((_) {});

  @override
  Pointer<Void> createEngine() {
    createCalls++;
    return Pointer<Void>.fromAddress(2);
  }

  @override
  void freeEngine(Pointer<Void> engine) {
    freed = true;
    onFree?.call();
  }

  @override
  void freeString(Pointer<Utf8> value) {}
}

class _FakeScanBridge implements ScanBridge {
  @override
  bool get hasScanOptionsApi => false;

  @override
  bool get hasQuickListApi => false;

  @override
  bool isScanRunning(Pointer<Void> engine) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class _FakeIndexBridge implements IndexBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class _FakeDeleteBridge implements DeleteBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class _FakeCapabilityBridge implements CapabilityBridge {
  _FakeCapabilityBridge({this.probeError});

  final Object? probeError;
  int probeCalls = 0;

  @override
  Map<String, dynamic> probeCapabilities(Pointer<Void> engine) {
    probeCalls++;
    final error = probeError;
    if (error != null) throw error;
    return const {'index_api': true};
  }

  @override
  bool isDeepScanReady(Pointer<Void> engine) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

class _FakeAiBridge implements AiBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
