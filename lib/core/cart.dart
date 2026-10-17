import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// One line in the cart: a dish, the choices made on it, and how many.
class CartLine {
  CartLine({
    required this.itemId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.optionIds = const [],
    this.optionNames = const [],
    this.imageUrl,
    this.veg,
  });

  final String itemId;
  final String name;

  /// Base price plus every chosen option, per unit: what one of these costs.
  final num unitPrice;
  int quantity;
  final List<String> optionIds;
  final List<String> optionNames;
  final String? imageUrl;
  final bool? veg;

  /// Two lines are the same line when it is the same dish with the same choices.
  String get key => '$itemId|${([...optionIds]..sort()).join(',')}';
  num get total => unitPrice * quantity;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'name': name,
        'unitPrice': unitPrice,
        'quantity': quantity,
        'optionIds': optionIds,
        'optionNames': optionNames,
        'imageUrl': imageUrl,
        'veg': veg,
      };

  factory CartLine.fromJson(Map<String, dynamic> j) => CartLine(
        itemId: '${j['itemId']}',
        name: '${j['name']}',
        unitPrice: j['unitPrice'] as num? ?? 0,
        quantity: (j['quantity'] as num? ?? 1).toInt(),
        optionIds: ((j['optionIds'] as List?) ?? const []).map((e) => '$e').toList(),
        optionNames: ((j['optionNames'] as List?) ?? const []).map((e) => '$e').toList(),
        imageUrl: j['imageUrl'] as String?,
        veg: j['veg'] as bool?,
      );
}

/// One shop's cart: what the customer has gathered from that shop and will check out as one order.
class ShopCart {
  ShopCart({required this.shopId, required this.shopHandle, required this.shopName, this.logoUrl, this.coupon, List<CartLine>? lines, DateTime? updatedAt})
      : lines = lines ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  final String shopId;
  final String shopHandle;
  final String shopName;
  final String? logoUrl;
  final List<CartLine> lines;
  DateTime updatedAt;

  /// A coupon code the customer applied in the cart, carried into checkout.
  String? coupon;

  bool get isEmpty => lines.isEmpty;
  int get count => lines.fold(0, (a, l) => a + l.quantity);
  num get subtotal => lines.fold<num>(0, (a, l) => a + l.total);

  Map<String, dynamic> toJson() => {
        'shopId': shopId,
        'shopHandle': shopHandle,
        'shopName': shopName,
        'logoUrl': logoUrl,
        'coupon': coupon,
        'updatedAt': updatedAt.toIso8601String(),
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  factory ShopCart.fromJson(Map<String, dynamic> j) => ShopCart(
        shopId: '${j['shopId']}',
        shopHandle: '${j['shopHandle']}',
        shopName: '${j['shopName']}',
        logoUrl: j['logoUrl'] as String?,
        coupon: j['coupon'] as String?,
        updatedAt: DateTime.tryParse('${j['updatedAt']}'),
        lines: ((j['lines'] as List?) ?? const []).map((l) => CartLine.fromJson(Map<String, dynamic>.from(l as Map))).toList(),
      );
}

/// The customer's carts, one per shop, as food apps keep them: an order goes to one shop, but a customer can be
/// building several at once and switch between them. The most recently touched cart comes first.
class Cart extends ChangeNotifier {
  Cart._();
  static final Cart instance = Cart._();

  static const _key = 'carts_v2';
  static const _legacyKey = 'cart_v1';
  static const _staleAfter = Duration(days: 14);

  final Map<String, ShopCart> _carts = {};
  DateTime _last = DateTime.fromMicrosecondsSinceEpoch(0);

  /// Strictly later than the one before, so "most recently touched" is never a tie.
  DateTime _stamp() {
    final now = DateTime.now();
    _last = now.isAfter(_last) ? now : _last.add(const Duration(microseconds: 1));
    return _last;
  }

  /// Every non-empty cart, most recently changed first.
  List<ShopCart> get carts => (_carts.values.where((c) => !c.isEmpty).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  ShopCart? cartFor(String shopId) {
    final c = _carts[shopId];
    return c == null || c.isEmpty ? null : c;
  }

  bool get isEmpty => carts.isEmpty;

  /// Items across every cart: what the tab badge shows.
  int get count => _carts.values.fold(0, (a, c) => a + c.count);

  /// Adds one of [item] with [chosen] options to this shop's cart, starting that cart if there is none.
  void add(Shop shop, MenuItem item, {List<Option> chosen = const [], int quantity = 1}) {
    final cart = _carts.putIfAbsent(shop.id, () => ShopCart(shopId: shop.id, shopHandle: shop.handle, shopName: shop.name, logoUrl: shop.logoUrl));
    final unit = chosen.fold<num>(item.price, (a, o) => a + o.price);
    final line = CartLine(
      itemId: item.id,
      name: item.name,
      unitPrice: unit,
      quantity: quantity,
      optionIds: chosen.map((o) => o.id).toList(),
      optionNames: chosen.map((o) => o.name).toList(),
      imageUrl: item.imageUrl,
      veg: item.veg,
    );
    final existing = cart.lines.where((l) => l.key == line.key);
    if (existing.isNotEmpty) {
      existing.first.quantity += quantity;
    } else {
      cart.lines.add(line);
    }
    cart.updatedAt = _stamp();
    notifyListeners();
    _save();
  }

  void setQuantity(String shopId, CartLine line, int quantity) {
    final cart = _carts[shopId];
    if (cart == null) return;
    if (quantity <= 0) {
      cart.lines.remove(line);
      if (cart.lines.isEmpty) _carts.remove(shopId);
    } else {
      line.quantity = quantity;
    }
    cart.updatedAt = _stamp();
    notifyListeners();
    _save();
  }

  void setCoupon(String shopId, String? code) {
    final cart = _carts[shopId];
    if (cart == null) return;
    cart.coupon = (code == null || code.trim().isEmpty) ? null : code.trim().toUpperCase();
    notifyListeners();
    _save();
  }

  /// Empties one shop's cart (it was ordered, or the customer cleared it). The others are untouched.
  void clearShop(String shopId) {
    if (_carts.remove(shopId) == null) return;
    notifyListeners();
    _save();
  }

  void clearAll() {
    _carts.clear();
    notifyListeners();
    _save();
  }

  /// How many of this dish (any choices) are in this shop's cart: what the menu's counter shows.
  int quantityOf(String shopId, String itemId) => cartFor(shopId)?.lines.where((l) => l.itemId == itemId).fold<int>(0, (a, l) => a + l.quantity) ?? 0;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final cutoff = DateTime.now().subtract(_staleAfter);
        for (final c in (j['carts'] as List?) ?? const []) {
          final cart = ShopCart.fromJson(Map<String, dynamic>.from(c as Map));
          // A cart left for two weeks has prices and availability nobody can vouch for any more.
          if (!cart.isEmpty && cart.updatedAt.isAfter(cutoff)) _carts[cart.shopId] = cart;
        }
      } else {
        // The single cart of earlier versions becomes one of the carts.
        final old = prefs.getString(_legacyKey);
        if (old != null) {
          final j = jsonDecode(old) as Map<String, dynamic>;
          final id = j['shopId'] as String?;
          final lines = ((j['lines'] as List?) ?? const []).map((l) => CartLine.fromJson(Map<String, dynamic>.from(l as Map))).toList();
          if (id != null && lines.isNotEmpty) {
            _carts[id] = ShopCart(shopId: id, shopHandle: '${j['shopHandle']}', shopName: '${j['shopName']}', lines: lines);
          }
          await prefs.remove(_legacyKey);
        }
      }
      notifyListeners();
    } catch (_) {
      // A damaged cart is an empty cart, never a crash on launch.
    }
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({'carts': carts.map((c) => c.toJson()).toList()}));
    } catch (_) {}
  }
}
