import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpik_customer/core/cart.dart';
import 'package:hyperpik_customer/core/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Shop _shop(String id) => Shop(id: id, handle: id, name: 'Shop $id', category: 'Food');

MenuItem _item(String id, {num price = 100, List<ChoiceGroup> groups = const []}) => MenuItem(id: id, name: 'Dish $id', price: price, groups: groups);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Cart.instance.clearAll();
  });

  group('menu parsing', () {
    test('a dish priced through a required choice shows its lowest price', () {
      final item = MenuItem.fromJson({
        'id': 'i1',
        'name': 'Manchurian',
        'price': 0,
        'choiceGroups': [
          {
            'id': 'g1',
            'name': 'Rice or noodles',
            'kind': 'variation',
            'min': 1,
            'max': 1,
            'options': [
              {'id': 'o1', 'name': 'Noodles', 'price': 119},
              {'id': 'o2', 'name': 'Rice', 'price': 99},
            ],
          },
        ],
      });
      expect(item.needsChoice, isTrue);
      expect(item.fromPrice, 99);
    });

    test('an optional add-on does not change the from price and is not required', () {
      final item = MenuItem.fromJson({
        'id': 'i1',
        'name': 'Rice',
        'price': 120,
        'choiceGroups': [
          {
            'id': 'g1',
            'name': 'Extras',
            'kind': 'addon',
            'min': 0,
            'max': 3,
            'options': [
              {'id': 'o1', 'name': 'Raita', 'price': 20}
            ],
          },
        ],
      });
      expect(item.needsChoice, isFalse);
      expect(item.fromPrice, 120);
    });

    test('a shop that is closed or out of range cannot be ordered from', () {
      expect(Shop.fromJson({'id': 'a', 'handle': 'a', 'name': 'A', 'open': false}).canOrder, isFalse);
      expect(Shop.fromJson({'id': 'a', 'handle': 'a', 'name': 'A', 'inRange': false}).canOrder, isFalse);
      expect(Shop.fromJson({'id': 'a', 'handle': 'a', 'name': 'A'}).canOrder, isTrue);
    });
  });

  group('shop offers', () {
    test('a shop page carries its live offers', () {
      final m = ShopMenu.fromJson({
        'shop': {'id': 's', 'handle': 's', 'name': 'S', 'category': {'label': 'Food'}},
        'offers': [
          {'title': '50% OFF up to ₹100', 'subtitle': null, 'code': 'SAVE50', 'minOrder': 199},
          {'title': 'Free delivery', 'subtitle': 'Over ₹299', 'code': null, 'minOrder': 0},
        ],
        'categories': [],
        'items': [],
      });
      expect(m.offers.length, 2);
      expect(m.offers.first.code, 'SAVE50');
      expect(m.offers.last.code, isNull);
    });
  });

  group('cart', () {
    test('the same dish with the same choices is one line', () {
      final c = Cart.instance;
      final o = Option(id: 'o1', name: 'Rice', price: 20);
      c.add(_shop('s'), _item('i', price: 100), chosen: [o]);
      c.add(_shop('s'), _item('i', price: 100), chosen: [o]);
      final cart = c.cartFor('s')!;
      expect(cart.lines.length, 1);
      expect(cart.lines.first.quantity, 2);
      expect(cart.lines.first.unitPrice, 120);
      expect(cart.subtotal, 240);
    });

    test('different choices are different lines', () {
      final c = Cart.instance;
      c.add(_shop('s'), _item('i'), chosen: [Option(id: 'a', name: 'A', price: 0)]);
      c.add(_shop('s'), _item('i'), chosen: [Option(id: 'b', name: 'B', price: 0)]);
      expect(c.cartFor('s')!.lines.length, 2);
      expect(c.quantityOf('s', 'i'), 2);
    });

    test('each shop keeps its own cart and the newest is first', () {
      final c = Cart.instance;
      c.add(_shop('s1'), _item('i1'));
      c.add(_shop('s2'), _item('i2'));
      expect(c.carts.length, 2);
      expect(c.carts.first.shopId, 's2');
      // Touching the first shop again brings its cart to the front without disturbing the other.
      c.add(_shop('s1'), _item('i3'));
      expect(c.carts.first.shopId, 's1');
      expect(c.cartFor('s2')!.lines.length, 1);
      expect(c.count, 3);
    });

    test('removing the last unit drops that cart only', () {
      final c = Cart.instance;
      c.add(_shop('s1'), _item('i1'));
      c.add(_shop('s2'), _item('i2'));
      c.setQuantity('s1', c.cartFor('s1')!.lines.first, 0);
      expect(c.cartFor('s1'), isNull);
      expect(c.cartFor('s2'), isNotNull);
      expect(c.isEmpty, isFalse);
    });

    test('clearing one shop leaves the others', () {
      final c = Cart.instance;
      c.add(_shop('s1'), _item('i1'));
      c.add(_shop('s2'), _item('i2'));
      c.clearShop('s1');
      expect(c.carts.map((x) => x.shopId), ['s2']);
    });

    test('carts survive a restart, and a legacy single cart becomes one of them', () async {
      SharedPreferences.setMockInitialValues({
        'cart_v1': '{"shopId":"old","shopHandle":"old","shopName":"Old Shop","lines":[{"itemId":"x","name":"X","unitPrice":50,"quantity":2}]}',
      });
      Cart.instance.clearAll();
      await Cart.instance.load();
      expect(Cart.instance.cartFor('old')?.subtotal, 100);
    });
  });
}
