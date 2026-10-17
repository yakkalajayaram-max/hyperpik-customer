import 'dart:io';

import 'package:flutter/foundation.dart' show DiagnosticLevel;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpik_customer/core/models.dart';
import 'package:hyperpik_customer/core/theme.dart';
import 'package:hyperpik_customer/features/home/home_screen.dart';

const _names = [
  'Food', 'Groceries', 'Pharmacy', 'Fruits & Vegetables', 'Meat & Fish', 'Bakery', 'Electronics', 'Beauty & Personal Care',
  'Pet Supplies', 'Stationery', 'Home & Kitchen', 'Flowers', 'Sweets', 'Gifting',
];

HomeData _data(int categories) {
  final cats = [for (var i = 0; i < categories; i++) Category(key: 'c$i', label: _names[i % _names.length], icon: '🛍️')];
  final rows = [
    for (final c in cats.take(4))
      TrendingRow(category: c, items: [
        for (var i = 0; i < 6; i++)
          TrendingItem(
            id: '${c.key}-$i',
            name: i.isEven ? 'A rather long product name that wraps over two lines $i' : 'Maida $i',
            price: 100 + i,
            fromPrice: i == 1,
            imageUrl: null,
            veg: i % 3 == 0 ? true : null,
            hasChoices: false,
            orders: i,
            shopHandle: 'shop',
            shopName: 'Ratandeep Supermarket and General Stores',
            shopOpen: i != 2,
            inRange: true,
            distanceKm: 1.2,
          ),
      ]),
  ];
  final shops = [
    Shop(id: 's1', handle: 's1', name: 'Ratandeep Supermarket and General Stores Kothapet', category: 'Groceries', city: 'Hyderabad', rating: 4.3, ratingCount: 120, prepMinutes: 25, distanceKm: 1.2, freeDeliveryOver: 299),
    Shop(id: 's2', handle: 's2', name: 'Tumyum Kitchen', category: 'Food', city: 'Hyderabad', open: false, closedReason: 'Closed - opens at 12:30', prepMinutes: 30),
    Shop(id: 's3', handle: 's3', name: 'Far Away Bakery', category: 'Bakery', inRange: false, distanceKm: 18.4),
  ];
  return HomeData(categories: cats, promos: const [], shops: shops, trending: rows);
}

Future<void> _pump(WidgetTester t, HomeData d, {double width = 360}) async {
  t.view.physicalSize = Size(width * 3, 2400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint('DETAILS: ${details.toString(minLevel: DiagnosticLevel.debug)}');
    prev?.call(details);
  };
  await t.pumpWidget(MaterialApp(theme: Hp.theme(Brightness.dark), home: HomeScreen(seed: d)));
  await t.pump();
}

void main() {
  setUpAll(() async {
    // The bundled face, so widths in the test are the widths on a phone and not the test font's square glyphs.
    final loader = FontLoader('PlusJakartaSans')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans.ttf').readAsBytesSync())));
    await loader.load();
  });

  for (final n in [1, 3, 8, 14]) {
    testWidgets('home lays out with $n categories and trending rows without overflow', (t) async {
      await _pump(t, _data(n));
      expect(tester(t), isNull);
      expect(find.text('Search stores & products'), findsOneWidget);
      if (n > 8) expect(find.text('More'), findsOneWidget);
      // The rails are lazy slivers: scroll down to Trending products, which must exist and lay out without overflow.
      await t.dragUntilVisible(find.text('Trending products'), find.byType(CustomScrollView), const Offset(0, -200));
      await t.pump();
      expect(find.text('Trending products'), findsOneWidget);
      expect(tester(t), isNull);
    });
  }

  for (final n in [1, 9]) {
    testWidgets('home golden with $n categories', (t) async {
      await _pump(t, _data(n));
      await t.pump(const Duration(milliseconds: 300));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/home$n.png'));
    });
  }

  testWidgets('narrow phone (320 px) does not overflow with 14 categories', (t) async {
    await _pump(t, _data(14), width: 320);
    expect(tester(t), isNull);
  });
}

/// Any layout exception raised while pumping (an overflow shows up here), or null.
Object? tester(WidgetTester t) {
  final e = t.takeException();
  if (e != null) debugPrint('LAYOUT EXCEPTION: $e');
  return e;
}
