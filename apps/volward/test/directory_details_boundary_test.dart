import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('directory page is composed of controllers and callback views', () {
    final controllers = <String, _UnitPin>{
      'lib/features/browse/controllers/directory_details_query.dart':
          const _UnitPin(900, 'class DirectoryQueryController'),
      'lib/features/browse/controllers/directory_details_actions.dart':
          const _UnitPin(700, 'class DirectoryDetailsActionsController'),
      'lib/features/browse/controllers/directory_browse_controller.dart':
          const _UnitPin(240, 'class DirectoryBrowseController'),
      'lib/features/browse/controllers/scan_presentation_controller.dart':
          const _UnitPin(240, 'class ScanPresentationController'),
      'lib/features/browse/controllers/directory_details_ports.dart':
          const _UnitPin(
            160,
            'abstract interface class DirectorySnapshotSource',
          ),
      'lib/features/browse/controllers/directory_details_page_base_state.dart':
          const _UnitPin(1150, 'abstract class DirectoryDetailsPageBaseState'),
    };
    final views = <String, _UnitPin>{
      'lib/features/browse/widgets/directory_top_nav.dart': const _UnitPin(
        140,
        'class DirectoryTopNav extends StatelessWidget',
      ),
      'lib/features/browse/widgets/directory_permission_banner.dart':
          const _UnitPin(
            240,
            'class DirectoryPermissionBanner extends StatelessWidget',
          ),
      'lib/features/browse/widgets/directory_compact_chrome.dart':
          const _UnitPin(
            220,
            'class DirectoryCompactChrome extends StatelessWidget',
          ),
      'lib/features/browse/widgets/directory_results_browser.dart':
          const _UnitPin(
            220,
            'class DirectoryResultsBrowser extends StatelessWidget',
          ),
      'lib/features/browse/widgets/directory_browse_results.dart':
          const _UnitPin(
            240,
            'class DirectoryBrowseResults extends StatelessWidget',
          ),
      'lib/features/browse/widgets/directory_scan_section.dart': const _UnitPin(
        220,
        'class DirectoryScanSection extends StatelessWidget',
      ),
      'lib/features/browse/widgets/directory_restore_loading.dart':
          const _UnitPin(
            320,
            'class DirectoryRestoreLoading extends StatelessWidget',
          ),
      'lib/features/browse/widgets/directory_sticky_section.dart':
          const _UnitPin(
            220,
            'class DirectoryDetailsStickyBar extends StatelessWidget',
          ),
    };
    const pagePin = _UnitPin(200, 'class DirectoryDetailsPage');

    _check('lib/directory_details_page.dart', pagePin);
    for (final entry in controllers.entries) {
      _check(entry.key, entry.value, forbidStateExtensions: true);
    }
    for (final entry in views.entries) {
      _check(entry.key, entry.value);
    }
  });
}

class _UnitPin {
  const _UnitPin(this.maxLines, this.signature);

  final int maxLines;
  final String signature;
}

void _check(String path, _UnitPin pin, {bool forbidStateExtensions = false}) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: path);
  final source = file.readAsStringSync();
  expect(file.readAsLinesSync().length, lessThan(pin.maxLines), reason: path);
  expect(source, contains(pin.signature), reason: path);
  expect(source, isNot(contains(RegExp(r'^part\s+', multiLine: true))));
  if (forbidStateExtensions) {
    // Controllers own their behavior as classes over narrow ports. They must
    // not be mixins or extensions attached to a page State.
    expect(source, isNot(contains('mixin ')), reason: path);
    expect(
      source,
      isNot(contains(RegExp(r'\bextension\s+\w+.*\bon\s+'))),
      reason: path,
    );
    expect(source, isNot(contains('on State<')), reason: path);
  }
}
