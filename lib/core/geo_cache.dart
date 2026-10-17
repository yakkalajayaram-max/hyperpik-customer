import 'dart:async';

/// A small time-limited memory for address lookups, with two callers asking the same thing at once sharing one request.
///
/// The same question gets asked again and again: the pin nudged a step, the search retyped, the app opened twice at home. Each
/// one that reaches the server is a request somebody serves; answered from here it is instant and free. Only real answers are
/// kept, so a failure or an empty list is asked again next time rather than remembered.
class TtlCache<T> {
  TtlCache({required this.max, required this.ttl});

  final int max;
  final Duration ttl;
  final Map<String, (T, DateTime)> _items = {};
  final Map<String, Future<T?>> _inflight = {};

  T? peek(String key) {
    final hit = _items.remove(key);
    if (hit == null) return null;
    if (hit.$2.isBefore(DateTime.now())) return null;
    _items[key] = hit; // most recently used goes last
    return hit.$1;
  }

  void put(String key, T value) {
    _items.remove(key);
    _items[key] = (value, DateTime.now().add(ttl));
    while (_items.length > max) {
      _items.remove(_items.keys.first);
    }
  }

  Future<T?> once(String key, Future<T?> Function() load, {bool Function(T)? keep}) {
    final hit = peek(key);
    if (hit != null) return Future.value(hit);
    final running = _inflight[key];
    if (running != null) return running;
    final f = () async {
      try {
        final v = await load();
        if (v != null && (keep == null || keep(v))) put(key, v);
        return v;
      } finally {
        _inflight.remove(key);
      }
    }();
    _inflight[key] = f;
    return f;
  }
}

/// A position rounded to [places] decimals: 4 is about 11 m (closer than two addresses can be told apart), 2 about 1.1 km.
double roundTo(double v, int places) {
  var f = 1.0;
  for (var i = 0; i < places; i++) {
    f *= 10;
  }
  return (v * f).roundToDouble() / f;
}

/// The text of a search ignoring case and spacing.
String queryKey(String q) => q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
