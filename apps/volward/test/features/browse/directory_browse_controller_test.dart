import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/features/browse/controllers/directory_browse_controller.dart';
import 'package:volward/scan_tree.dart';

void main() {
  test('directory selection keeps the newest visible children', () async {
    final oldGate = Completer<void>();
    final browse = DirectoryBrowseController.forTest(
      selectionLoader: (path) async {
        if (path == '/old') await oldGate.future;
      },
    );

    final oldSelection = browse.selectDirectory('/old');
    await browse.selectDirectory('/new');
    oldGate.complete();
    await oldSelection;

    expect(browse.currentPath, '/new');
  });

  test('column navigation and selection are owned by the controller', () {
    final browse = DirectoryBrowseController.forTest();
    var notifications = 0;
    browse.addListener(() => notifications++);

    browse.columnChain.add(
      ScanTreeNode(name: 'a', path: '/a', isDirectory: true),
    );
    browse.resetColumnNavigation();
    browse.selected.add('entry');
    browse.clearSelection();

    expect(browse.columnChain, isEmpty);
    expect(browse.columnNavTick.value, 1);
    expect(browse.selected, isEmpty);
    expect(notifications, 0);
  });
}
