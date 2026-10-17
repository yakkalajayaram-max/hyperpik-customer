import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';

/// The shops this customer has hearted. Held in memory and updated at once on a tap, then confirmed with the server; if the
/// server refuses, the heart goes back.
class Favourites extends ChangeNotifier {
  Favourites._();
  static final Favourites instance = Favourites._();

  final Set<String> _ids = {};
  bool loaded = false;

  bool contains(String shopId) => _ids.contains(shopId);
  int get count => _ids.length;

  Future<void> load() async {
    if (Api.user == null) {
      _ids.clear();
      loaded = false;
      notifyListeners();
      return;
    }
    try {
      final shops = await Api.favourites();
      _ids
        ..clear()
        ..addAll(shops.map((s) => s.id));
      loaded = true;
      notifyListeners();
    } catch (_) {
      // A heart that cannot load is simply empty.
    }
  }

  /// Returns false when the customer must sign in first.
  Future<bool> toggle(String shopId) async {
    if (Api.user == null) return false;
    final had = _ids.contains(shopId);
    had ? _ids.remove(shopId) : _ids.add(shopId);
    HapticFeedback.lightImpact();
    notifyListeners();
    try {
      final now = await Api.toggleFavourite(shopId);
      now ? _ids.add(shopId) : _ids.remove(shopId);
    } catch (_) {
      had ? _ids.add(shopId) : _ids.remove(shopId);
    }
    notifyListeners();
    return true;
  }
}
