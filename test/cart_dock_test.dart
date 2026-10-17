import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpik_customer/core/cart.dart';
import 'package:hyperpik_customer/core/cart_dock.dart';
import 'package:hyperpik_customer/core/models.dart';
import 'package:hyperpik_customer/core/theme.dart';
import 'package:hyperpik_customer/features/cart/cart_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Shop _shop(String id, String name) => Shop(id: id, handle: id, name: name, category: 'Food');
MenuItem _item(String id, String name, num price) => MenuItem(id: id, name: name, price: price, groups: const []);

Widget _app(Widget home, {bool dock = true}) => MaterialApp(
      theme: Hp.theme(Brightness.light),
      navigatorKey: appNavigatorKey,
      navigatorObservers: [DockRouteObserver()],
      builder: (context, child) => Stack(children: [if (child != null) child, if (dock) const CartDock()]),
      home: home,
    );

void main() {
  setUpAll(() async {
    final loader = FontLoader('PlusJakartaSans')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans.ttf').readAsBytesSync())));
    await loader.load();
  });

  setUp(() {
    // The payment plugin has no phone to talk to in a test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('razorpay_flutter'), (call) async => null);
    SharedPreferences.setMockInitialValues({});
    Cart.instance.clearAll();
    DockGate.holds.value = 0;
  });

  Future<void> size(WidgetTester t, {double w = 390, double h = 844}) async {
    t.view.physicalSize = Size(w * 3, h * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('the dock is hidden with no carts and shows one card per cart', (t) async {
    await size(t);
    await t.pumpWidget(_app(const Scaffold(body: Center(child: Text('home')))));
    await t.pump();
    expect(find.text('View Cart'), findsNothing);

    Cart.instance.add(_shop('a', 'Tumyum Kitchen'), _item('1', 'Sweet Corn Soup', 89), quantity: 2);
    Cart.instance.add(_shop('b', 'Ratandeep Supermarket'), _item('2', 'Maida 1 kg', 100));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // Newest cart leads; its card shows the shop, the count and the total.
    expect(find.textContaining('Ratandeep Supermarket'), findsOneWidget);
    expect(find.textContaining('1 item'), findsOneWidget);
    await t.drag(find.byType(PageView), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('Tumyum Kitchen'), findsOneWidget);
    expect(find.textContaining('2 items'), findsOneWidget);
  });

  testWidgets('dock golden with three carts', (t) async {
    await size(t);
    await t.pumpWidget(_app(Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: ListView(children: [for (var i = 0; i < 12; i++) ListTile(title: Text('A shop row $i'))]),
      bottomNavigationBar: NavigationBar(selectedIndex: 0, destinations: const [
        NavigationDestination(icon: Icon(Icons.storefront), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), label: 'Cart'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
      ]),
    )));
    Cart.instance.add(_shop('a', 'Tumyum Kitchen'), _item('1', 'Sweet Corn Soup', 89), quantity: 2);
    Cart.instance.add(_shop('b', 'Ratandeep Supermarket'), _item('2', 'Maida 1 kg', 100));
    Cart.instance.add(_shop('c', 'Green Leaf Fruits & Vegetables'), _item('3', 'Bananas', 60), quantity: 3);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/dock.png'));
  });

  testWidgets('the cart page shows the bag, a chip per cart and asks a guest to log in', (t) async {
    await size(t);
    Cart.instance.add(_shop('a', 'Tumyum Kitchen'), _item('1', 'Sweet Corn Soup', 89), quantity: 2);
    Cart.instance.add(_shop('b', 'Ratandeep Supermarket'), _item('2', 'Maida 1 kg', 100));
    await t.pumpWidget(_app(const CartScreen(), dock: false));
    await t.pump();
    // One page for the bag and the checkout; the other shop's bag is one tap away on a chip.
    expect(find.text('Cart & checkout'), findsOneWidget);
    expect(find.text('Ratandeep Supermarket'), findsOneWidget);
    expect(find.text('Tumyum Kitchen'), findsOneWidget);
    expect(find.text('Log in to check out'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/carts.png'));
  });
}
