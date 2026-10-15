import 'package:flutter_test/flutter_test.dart';
import 'package:volward/ai/ai_candidates_materialized_cache.dart';

void main() {
  test('loadOrReuse returns cached raw without second load', () async {
    final cache = AiCandidatesMaterializedCache.instance;
    cache.clear('snap-a');
    var loads = 0;
    final first = await cache.loadOrReuse('snap-a', () async {
      loads++;
      return 'spill:/tmp/x.pb';
    });
    final second = await cache.loadOrReuse('snap-a', () async {
      loads++;
      return 'spill:/tmp/y.pb';
    });
    expect(first, 'spill:/tmp/x.pb');
    expect(second, 'spill:/tmp/x.pb');
    expect(loads, 1);
    cache.clear('snap-a');
  });
}
