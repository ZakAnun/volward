import 'dart:io';

import '../snapshot_cache.dart';

/// Shared location for theme, locale, accent, update and AI preferences.
///
/// Theme settings own `theme_preference`, `locale_preference`, `accent_color`
/// and `auto_download_updates`. AI settings own the AI mode, provider,
/// privacy consent, Coverage budgets, and conclusion preferences. Linux desktop
/// integration owns the desktop entry executable path. Each owner performs its
/// own read/modify/write. BYOK usage has a separate file and lock, and
/// credentials are stored separately.
File sharedSettingsFile() =>
    File('${SnapshotCache.cacheDir().path}/settings.json');
