import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_candidates_materialized_cache.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('volward-cand-cache-');
  });

  tearDown(() {
    AiCandidatesMaterializedCache.instance.clear('snap-a');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File spill(String name) => File('${tmp.path}/$name')..writeAsStringSync('x');

  test('loadOrReuse returns cached raw without second load', () async {
    final cache = AiCandidatesMaterializedCache.instance;
    final x = spill('x.pb');
    final y = spill('y.pb');
    var loads = 0;
    final first = await cache.loadOrReuse('snap-a', () async {
      loads++;
      return 'spill:${x.path}';
    });
    final second = await cache.loadOrReuse('snap-a', () async {
      loads++;
      return 'spill:${y.path}';
    });
    expect(first, 'spill:${x.path}');
    expect(second, 'spill:${x.path}');
    expect(loads, 1);
  });

  test('loadOrReuse rebuilds when cached spill file is gone', () async {
    final cache = AiCandidatesMaterializedCache.instance;
    final x = spill('x.pb');
    final y = spill('y.pb');
    await cache.loadOrReuse('snap-a', () async => 'spill:${x.path}');
    x.deleteSync();

    var loads = 0;
    final second = await cache.loadOrReuse('snap-a', () async {
      loads++;
      return 'spill:${y.path}';
    });
    expect(second, 'spill:${y.path}');
    expect(loads, 1);
  });

  test('clear and replacement delete the owned spill file', () async {
    final cache = AiCandidatesMaterializedCache.instance;
    final x = spill('x.pb');
    final y = spill('y.pb');
    cache.putRaw('snap-a', 'spill:${x.path}');
    cache.putRaw('snap-a', 'spill:${y.path}');
    expect(x.existsSync(), isFalse);
    expect(y.existsSync(), isTrue);

    cache.clear('snap-a');
    expect(y.existsSync(), isFalse);
  });
}
