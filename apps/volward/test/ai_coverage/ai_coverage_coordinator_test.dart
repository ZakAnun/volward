import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_coverage_coordinator.dart';
import 'package:volward/ai/coverage_job_state.dart';
import 'package:volward/ai/coverage_notification_text.dart';
import 'package:volward/l10n/generated/app_localizations_en.dart';

void main() {
  test('coordinator emits desktop notify on completion', () async {
    final notifications = <String>[];
    final coordinator = AiCoverageCoordinator.testing(
      desktopNotify: ({required title, required body}) async {
        notifications.add('$title::$body');
      },
    );

    const state = CoverageJobState(
      snapshotId: 's1',
      rootPath: '/',
      planVersion: 1,
      cursor: 10,
      totalUnclassified: 10,
      analyzedFiles: 10,
      preClassifiedCount: 0,
      status: CoverageJobStatus.completed,
      usedTokens: 100,
      usedCredits: 0,
      budgetTokens: 1000,
      budgetCredits: 0,
      updatedAtMs: 1,
    );
    final l10n = AppLocalizationsEn();

    await coordinator.debugNotify(state, l10n: l10n);

    expect(notifications, hasLength(1));
    final copy = coverageCompleteNotification(l10n, state);
    expect(notifications.single, '${copy.title}::${copy.body}');
  });
}
