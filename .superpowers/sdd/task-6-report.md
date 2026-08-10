# Task 6 Report: AppUpdater state machine

## Status

PASS

## Implementation

- Added `AppUpdater` as a `ChangeNotifier`-backed state machine.
- Implemented check transitions for available, up-to-date, no matching asset, unsupported runtime, and network failures.
- Silent checks return to idle on all failures; manual checks expose typed errors.
- Implemented download progress, installing transition, and download/install failure classification.
- Implemented session-only prompt dismissal.
- Implemented release-page opening with the required fallback:
  `https://github.com/ZakAnun/volward/releases/latest`.

## TDD evidence

### RED

Command:

`flutter test test/updater/app_updater_test.dart`

Result: failed as expected because `lib/updater/app_updater.dart` and
`AppUpdater` did not exist.

### GREEN

Command:

`flutter test test/updater/app_updater_test.dart`

Result: PASS, 8 tests.

Covered:

- newer remote release becomes available and resolves the platform asset
- equal version becomes up to date
- silent and manual network-error behavior
- download reaches installer
- session prompt dismissal
- release URL opening
- no-matching-asset failure

## Additional verification

- `flutter analyze lib/updater/app_updater.dart test/updater/app_updater_test.dart`
  — PASS, no issues.
- `flutter test` — PASS, 178 tests.
- The first full-suite attempt found missing generated localization files.
  Running `flutter gen-l10n` restored the tracked generated files, after which
  the complete suite passed without repository changes to those files.

## Files

- `apps/volward/lib/updater/app_updater.dart`
- `apps/volward/test/updater/app_updater_test.dart`

## Concerns

None.

## Spec/quality review fix

Addressed the review findings:

- Silent checks now return to `idle` for missing assets and unsupported
  runtimes; manual checks continue to expose typed errors.
- `downloadAndInstall()` now rejects every phase except `available`.
- `dismissAvailable()` always records dismissal, but only changes state from
  `available` to `idle`.

TDD regression evidence:

- RED: 4 failures covering silent missing assets, silent unsupported runtime,
  repeated install from `installing`, and dismissal outside `available`.
- GREEN: `flutter test test/updater/app_updater_test.dart` — PASS, 12 tests.
- `flutter analyze lib/updater/app_updater.dart
  test/updater/app_updater_test.dart` — PASS, no issues.
