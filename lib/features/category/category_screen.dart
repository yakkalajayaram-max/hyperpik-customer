import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/nav.dart';
import '../../core/place.dart';
import '../../core/site_chrome.dart';
import '../../core/cart_dock.dart';
import '../../core/theme.dart';
import '../home/home_screen.dart';

/// A category's colour, from its admin-set hex, or the Hyperpik purple.
Color categoryColor(Category c) {
  final h = (c.colorHex ?? '').replaceAll('#', '');
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return Hp.accent;
}

/// The height a [CategoryTile] needs in a grid row: the icon, and up to two lines of label, which grow with the phone's
/// text size.
double categoryTileExtent(BuildContext context, {double inset = 32, int columns = 4}) {
  final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
  return 12 + 30 + 6 + 2 * 16 * scale + 12 + 1.6;
}

/// A category as the design shows it: a large icon straight on the page with its name under it.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, this.count, this.selected = false, this.onTap});
  final Category category;
  final int? count;
  final bool selected;

  /// What a tap does; by default it brings the category to Home, where the website shows its shops.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = category.shops == 0 && (count ?? 0) == 0 && category.key.isNotEmpty && category.shops == 0;
    // A boxed tile, like the website's: a bordered card with the icon over its name.
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap ??
          () {
            Navigator.of(context).popUntil((r) => r.isFirst);
            shellTab.value = tabHome;
            homeCategory.value = category.key;
          },
      child: Ink(
        decoration: BoxDecoration(
          color: Hp.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Hp.accent : Hp.line(context), width: selected ? 2 : 0.8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Column(children: [
          SizedBox(height: 30, child: Center(child: Text(category.icon ?? '🛍️', style: TextStyle(fontSize: 30.4, height: 1, color: empty ? Colors.white.withValues(alpha: 0.85) : null)))),
          const SizedBox(height: 6),
          Expanded(child: Text(category.label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

/// Every category, when there are more than fit on Home.
class AllCategoriesScreen extends StatelessWidget {
  const AllCategoriesScreen({super.key, required this.categories, this.counts = const {}});
  final List<Category> categories;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All categories')),
      body: GridView(
        padding: const EdgeInsets.all(16),
        // A 70 px icon plate and up to two lines of label, which grow with the phone's text size.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 10,
          mainAxisExtent: categoryTileExtent(context),
        ),
        children: [for (final c in categories) CategoryTile(category: c, count: counts[c.label])],
      ),
    );
  }
}

/// The shops in one category, with its own colour and the same quick filters as Home.
class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.category});
  final Category category;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  HomeData? _data;
  String? _error;
  String _query = '';
  bool _searching = false;
  Timer? _debounce;

  String _sort = 'relevance';
  double _minRating = 0;
  int _maxMinutes = 0;
  bool _openOnly = false;
  bool _nearOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = Place.instance;
      final d = await Api.home(lat: p.isCurrent ? p.lat : null, lng: p.isCurrent ? p.lng : null, category: widget.category.key, query: _query);
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<Shop> _visible() {
    final list = (_data?.shops ?? const <Shop>[]).where((s) {
      if (_openOnly && !s.open) return false;
      if (_nearOnly && !(s.distanceKm != null && s.distanceKm! <= 3)) return false;
      if (_minRating > 0 && !(s.ratingCount > 0 && s.rating >= _minRating)) return false;
      if (_maxMinutes > 0 && !(s.prepMinutes > 0 && s.prepMinutes <= _maxMinutes)) return false;
      return true;
    }).toList();
    switch (_sort) {
      case 'rating':
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case 'time':
        list.sort((a, b) => (a.prepMinutes == 0 ? 999 : a.prepMinutes).compareTo(b.prepMinutes == 0 ? 999 : b.prepMinutes));
      case 'distance':
        list.sort((a, b) => (a.distanceKm ?? 999).compareTo(b.distanceKm ?? 999));
    }
    return list;
  }

  /// One option sheet for a dropdown chip: the choices, the current one ticked.
  Future<T?> _pick<T>(String title, List<(T, String)> options, T current) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          for (final o in options)
            ListTile(
              title: Text(o.$2, style: TextStyle(fontWeight: o.$1 == current ? FontWeight.w900 : FontWeight.w600)),
              trailing: o.$1 == current ? const Icon(Icons.check_rounded, color: Hp.accentHi) : null,
              onTap: () => Navigator.pop(ctx, o.$1),
            ),
        ]),
      ),
    );
  }

  Widget _dropdown(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active ? Hp.accent.withValues(alpha: 0.22) : Hp.surface(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? Hp.accentHi : Hp.line(context)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: active ? Colors.white : null)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _toggle(String label, bool on, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: on ? Hp.accent : Hp.surface(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? Hp.accent : Hp.line(context)),
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: on ? Colors.white : null)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final shops = _visible();
    final dishes = _query.trim().isEmpty ? const <TrendingItem>[] : (_data?.dishes ?? const <TrendingItem>[]);
    const sortLabels = {'relevance': 'Relevance', 'rating': 'Rating', 'time': 'Delivery time', 'distance': 'Distance'};

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: InputDecoration(hintText: 'Search in ${c.label}', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () {
                    _query = v;
                    _load();
                  });
                },
              )
            : Text(c.label),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching && _query.isNotEmpty) {
                _query = '';
                _load();
              }
            }),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    _dropdown(_sort == 'relevance' ? 'Sort' : sortLabels[_sort]!, _sort != 'relevance', () async {
                      final v = await _pick<String>('Sort by', [for (final e in sortLabels.entries) (e.key, e.value)], _sort);
                      if (v != null) setState(() => _sort = v);
                    }),
                    _dropdown(_minRating == 0 ? 'Rating' : 'Rating ${_minRating.toStringAsFixed(1)}+', _minRating > 0, () async {
                      final v = await _pick<double>('Minimum rating', const [(0.0, 'Any'), (3.5, '3.5 and above'), (4.0, '4.0 and above'), (4.5, '4.5 and above')], _minRating);
                      if (v != null) setState(() => _minRating = v);
                    }),
                    _dropdown(_maxMinutes == 0 ? 'Delivery time' : 'Under $_maxMinutes min', _maxMinutes > 0, () async {
                      final v = await _pick<int>('Delivery time', const [(0, 'Any'), (20, 'Under 20 minutes'), (30, 'Under 30 minutes'), (45, 'Under 45 minutes')], _maxMinutes);
                      if (v != null) setState(() => _maxMinutes = v);
                    }),
                    _toggle('Open now', _openOnly, () => setState(() => _openOnly = !_openOnly)),
                    _toggle('Within 3 km', _nearOnly, () => setState(() => _nearOnly = !_nearOnly)),
                  ],
                ),
              ),
            ),
            if (dishes.isNotEmpty) ...[
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 12, 20, 8), child: Text('Dishes', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)))),
              SliverList.builder(itemCount: dishes.length, itemBuilder: (_, i) => DishResultTile(item: dishes[i])),
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, 8), child: Text('Stores', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)))),
            ],
            if (_error != null)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [Text(_error!), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Try again'))])))
            else if (_data == null)
              SliverList.list(children: const [ShopSkeleton(), ShopSkeleton()])
            else if (shops.isEmpty)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(48), child: Center(child: Text('No ${c.label.toLowerCase()} shops match.', textAlign: TextAlign.center))))
            else
              SliverList.builder(itemCount: shops.length, itemBuilder: (_, i) => ShopCard(shop: shops[i])),
            const SliverToBoxAdapter(child: DockSpacer(base: 28)),
          ],
        ),
      ),
    );
  }
}
