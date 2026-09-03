import 'package:flutter_test/flutter_test.dart';
import 'package:volward/directory_details_page.dart';

void main() {
  test('progress-only session ticks do not flush the page', () {
    expect(
      sessionUiFlushFor(
        snapshotIdChanged: false,
        catalogChanged: false,
        targetPreviewChanged: false,
        deletingChanged: false,
        refreshingChanged: false,
        postDeleteRefreshChanged: false,
        scanStarted: false,
        scanStopped: false,
      ),
      SessionUiFlush.none,
    );
  });

  test('catalog change flushes browse, not the whole page', () {
    expect(
      sessionUiFlushFor(
        snapshotIdChanged: false,
        catalogChanged: true,
        targetPreviewChanged: false,
        deletingChanged: false,
        refreshingChanged: false,
        postDeleteRefreshChanged: false,
        scanStarted: false,
        scanStopped: false,
        browseResultsLayoutChanged: false,
      ),
      SessionUiFlush.browseResults,
    );
  });

  test('snapshot change that flips browse results layout flushes the page', () {
    expect(
      sessionUiFlushFor(
        snapshotIdChanged: true,
        catalogChanged: false,
        targetPreviewChanged: false,
        deletingChanged: false,
        refreshingChanged: false,
        postDeleteRefreshChanged: false,
        scanStarted: false,
        scanStopped: false,
        browseResultsLayoutChanged: true,
      ),
      SessionUiFlush.page,
    );
  });

  test('catalog change that flips browse results layout flushes the page', () {
    expect(
      sessionUiFlushFor(
        snapshotIdChanged: false,
        catalogChanged: true,
        targetPreviewChanged: false,
        deletingChanged: false,
        refreshingChanged: false,
        postDeleteRefreshChanged: false,
        scanStarted: false,
        scanStopped: false,
        browseResultsLayoutChanged: true,
      ),
      SessionUiFlush.page,
    );
  });

  test('scan start flushes the page', () {
    expect(
      sessionUiFlushFor(
        snapshotIdChanged: false,
        catalogChanged: false,
        targetPreviewChanged: false,
        deletingChanged: false,
        refreshingChanged: false,
        postDeleteRefreshChanged: false,
        scanStarted: true,
        scanStopped: false,
      ),
      SessionUiFlush.page,
    );
  });
}
