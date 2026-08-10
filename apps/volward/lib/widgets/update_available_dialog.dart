import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/apple_tokens.dart';
import '../updater/app_updater.dart';
import '../updater/update_models.dart';
import 'apple_widgets.dart';

String summarizeReleaseNotes(String? body, {int maxChars = 400}) {
  final text = (body ?? '').trim();
  if (text.isEmpty) return '';
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars).trimRight()}…';
}

Future<void> showUpdateFailureDialog({
  required BuildContext context,
  required AppUpdater updater,
}) async {
  final l10n = context.l10n;
  final openDownloadPage = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.settingsUpdateError(updater.status.errorMessage ?? '')),
      actions: [
        AppleButton(
          label: l10n.settingsUpdateLater,
          variant: AppleButtonVariant.pearl,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        AppleButton(
          label: l10n.settingsOpenDownloadPage,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (openDownloadPage == true) {
    await updater.openDownloadPage();
  }
  updater.dismissErrorPrompt();
}

Future<void> showUpdateAvailableDialog({
  required BuildContext context,
  required AppUpdater updater,
}) async {
  final release = updater.status.release;
  if (release == null) return;
  final l10n = context.l10n;
  final notes = summarizeReleaseNotes(release.body);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.updateAvailableTitle(release.version)),
      content: Text(
        notes.isEmpty
            ? l10n.updateNotesUnavailable
            : l10n.updateAvailableMessage(notes),
      ),
      actions: [
        AppleButton(
          label: l10n.settingsUpdateLater,
          variant: AppleButtonVariant.pearl,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        AppleButton(
          label: l10n.settingsUpdateNow,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (result == true) {
    await updater.downloadAndInstall();
    if (updater.status.phase == UpdatePhase.error && context.mounted) {
      await showUpdateFailureDialog(context: context, updater: updater);
    }
  } else {
    updater.dismissAvailable();
  }
}
