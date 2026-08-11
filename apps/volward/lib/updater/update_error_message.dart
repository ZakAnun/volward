import '../l10n/generated/app_localizations.dart';
import 'update_models.dart';

/// Formats an [UpdateStatus] error for UI, distinguishing check-time failures
/// from download/install-time failures.
String formatUpdateStatusError(AppLocalizations l10n, UpdateStatus status) {
  final error = status.errorMessage ?? '';
  switch (status.failureKind) {
    case UpdateFailureKind.download:
    case UpdateFailureKind.install:
    case UpdateFailureKind.integrity:
      return l10n.settingsUpdateActionError(error);
    case UpdateFailureKind.network:
    case UpdateFailureKind.noMatchingAsset:
    case UpdateFailureKind.unsupportedRuntime:
    case null:
      return l10n.settingsUpdateError(error);
  }
}
