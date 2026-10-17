import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpik_customer/core/geo_cache.dart';

void main() {
  test('the same question is answered once, even when asked together', () async {
    final c = TtlCache<int>(max: 5, ttl: const Duration(minutes: 1));
    var calls = 0;
    Future<int?> load() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return 7;
    }

    final both = await Future.wait([c.once('a', load), c.once('a', load)]);
    expect(both, [7, 7]);
    expect(await c.once('a', load), 7);
    expect(calls, 1);
  });

  test('a failure or an empty answer is asked again, not remembered', () async {
    final c = TtlCache<List<int>>(max: 5, ttl: const Duration(minutes: 1));
    var calls = 0;
    Future<List<int>?> load() async {
      calls++;
      return <int>[];
    }

    await c.once('q', load, keep: (v) => v.isNotEmpty);
    await c.once('q', load, keep: (v) => v.isNotEmpty);
    expect(calls, 2);
    Future<List<int>?> boom() async => throw Exception('down');
    await expectLater(c.once('x', boom), throwsException);
    expect(await c.once('x', () async => [1]), [1]);
  });

  test('the oldest entry goes first and expired ones are not served', () async {
    final c = TtlCache<int>(max: 2, ttl: const Duration(milliseconds: 30));
    c.put('a', 1);
    c.put('b', 2);
    c.put('c', 3);
    expect(c.peek('a'), isNull);
    expect(c.peek('c'), 3);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.peek('c'), isNull);
  });

  test('positions and searches are rounded to one key', () {
    expect(roundTo(17.385044, 4), 17.385);
    expect(roundTo(17.38504, 2), 17.39);
    expect(queryKey('  Banjara   HILLS '), 'banjara hills');
  });
}
