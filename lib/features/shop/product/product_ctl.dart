import 'package:flutter/foundation.dart';

import '../../../core/models.dart';

/// What the customer chose on the product page: the options, how many, and whether they pressed "Buy now".
typedef ItemChoice = ({List<Option> chosen, int quantity, bool buyNow});

/// The state every product layout shares: which options are picked, how many, whether the item can be bought and what the
/// button says. The layouts only differ in how they look; none of them has its own rules about choices or price, so a size
/// can never be required on one page and optional on another.
///
/// Nothing is pre-selected: defaulting a required choice would charge for a size or portion the customer never picked.
class ProductCtl extends ChangeNotifier {
  ProductCtl({required this.item, required this.shop, required this.canOrder, this.blockedReason});

  final MenuItem item;
  final Shop shop;
  final bool canOrder;
  final String? blockedReason;

  final Map<String, Set<String>> _picked = {};
  int qty = 1;
  String? error;

  List<ChoiceGroup> get groups => item.groups;

  /// Only a variation counts as compulsory: it says WHICH item this is. A minimum on an add-on is a mistake by the shop.
  bool required(ChoiceGroup g) => g.isVariation && g.min > 0;

  List<ChoiceGroup> get unanswered => groups.where((g) => required(g) && (_picked[g.id]?.length ?? 0) < g.min).toList();

  bool isPicked(ChoiceGroup g, Option o) => _picked[g.id]?.contains(o.id) ?? false;

  List<Option> get chosen => [
        for (final g in groups) for (final o in g.options) if (isPicked(g, o)) o,
      ];

  num get unit => chosen.fold<num>(item.price, (a, o) => a + o.price);
  num get total => unit * qty;

  /// The printed MRP, shown struck through when it is above the selling price. It stands for the base item, so an item priced
  /// through its options (base price zero) shows none, rather than a discount worked out against the wrong number.
  num? get mrp {
    final m = item.product?.mrp;
    if (m == null || m <= 0 || item.price <= 0) return null;
    return m > item.price ? m : null;
  }

  /// "62% OFF", or null when there is no MRP above the price.
  int? get discountPercent {
    final m = mrp;
    if (m == null) return null;
    final pct = ((m - item.price) / m * 100).round();
    return pct >= 1 ? pct : null;
  }

  bool get soldOut => !item.available || !canOrder;

  bool get ready => unanswered.isEmpty;

  /// What the main button says, so every layout words it the same way.
  String buttonLabel(String verb) {
    if (!canOrder) return blockedReason ?? 'Not available right now';
    if (!item.available) return item.unavailableLabel ?? 'Out of stock';
    if (!ready) return 'Select ${unanswered.map((g) => g.name.toLowerCase()).join(' and ')}';
    return '$verb · ₹${total.toStringAsFixed(0)}';
  }

  void toggle(ChoiceGroup g, Option o) {
    final set = _picked.putIfAbsent(g.id, () => {});
    error = null;
    if (set.contains(o.id)) {
      set.remove(o.id);
    } else if (g.max <= 1) {
      // max 1 behaves as a radio: picking replaces rather than accumulates.
      set
        ..clear()
        ..add(o.id);
    } else if (set.length < g.max) {
      set.add(o.id);
    }
    notifyListeners();
  }

  void setQty(int v) {
    qty = v < 1 ? 1 : v;
    notifyListeners();
  }

  /// Returns the choice to hand back, or null (and sets [error]) when a required choice is still open.
  ItemChoice? submit({bool buyNow = false}) {
    final un = unanswered;
    if (un.isNotEmpty) {
      error = 'Please choose ${un.map((g) => g.name).join(' and ')}.';
      notifyListeners();
      return null;
    }
    return (chosen: chosen, quantity: qty, buyNow: buyNow);
  }
}
