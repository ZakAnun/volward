import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_settings_store.dart';
import 'package:volward/features/ai_coverage/ports/workspace_ports.dart';

void main() {
  test('workspace ports delegate without feature singleton reads', () async {
    final analytics = _FakeAnalyticsPort();
    final settings = _FakeSettingsPort();
    final auth = _FakeAuthPort();
    final cache = _FakeCandidateCachePort();
    final coverage = _FakeCoverageJobs();
    final ports = AiWorkspacePorts(
      analytics: analytics,
      settings: settings,
      auth: auth,
      coverageJobs: coverage,
      candidateCache: cache,
    );

    await ports.analytics.track('event', {'value': 1});
    await ports.settings.coverageBudgetForMode(AiMode.platform);
    expect(await ports.auth.hasAuthenticatedUser(), isTrue);
    expect(ports.coverageJobs, same(coverage));
    ports.candidateCache.clearSnapshot('snapshot');

    expect(analytics.events, ['event']);
    expect(settings.modes, [AiMode.platform]);
    expect(cache.cleared, ['snapshot']);
  });

  test('feature port contracts contain no production singleton adapters', () {
    final source = File(
      'lib/features/ai_coverage/ports/workspace_ports.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('Analytics.instance')));
    expect(source, isNot(contains('AiSettingsStore.instance')));
    expect(source, isNot(contains('PlatformAuthStore.instance')));
    expect(source, isNot(contains('AiCoverageCoordinator.instance')));
    expect(source, isNot(contains('AiCandidatesMaterializedCache.instance')));
  });
}

class _FakeAnalyticsPort implements WorkspaceAnalyticsPort {
  final List<String> events = [];

  @override
  Future<void> track(String name, [Map<String, Object?>? props]) async {
    events.add(name);
  }
}

class _FakeSettingsPort implements WorkspaceSettingsPort {
  final List<AiMode> modes = [];

  @override
  Future<ByokTokenUsageTotals> addByokTokenUsage({
    required int inputTokens,
    required int outputTokens,
    required int totalTokens,
    required bool estimated,
    required bool partial,
  }) async {
    return ByokTokenUsageTotals.empty;
  }

  @override
  Future<bool> conclusionNarrativeAuto() async => true;

  @override
  Future<bool> conclusionNarrativeEnabled() async => false;

  @override
  Future<({int tokens, int credits})> coverageBudgetForMode(AiMode mode) async {
    modes.add(mode);
    return (tokens: 1, credits: 1);
  }

  @override
  Future<int> resolveRunBudgetCredits({
    required int estimatedCredits,
    required int accountBalance,
  }) async {
    return estimatedCredits;
  }

  @override
  Future<void> setCoverageBudgetCredits(int credits) async {}

  @override
  Future<void> setCoverageBudgetTokens(int tokens) async {}
}

class _FakeAuthPort implements WorkspaceAuthPort {
  @override
  Future<bool> hasAuthenticatedUser() async => true;
}

class _FakeCandidateCachePort implements WorkspaceCandidateCachePort {
  final List<String> cleared = [];

  @override
  void clearSnapshot(String snapshotId) => cleared.add(snapshotId);
}

class _FakeCoverageJobs implements WorkspaceCoverageJobsPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
