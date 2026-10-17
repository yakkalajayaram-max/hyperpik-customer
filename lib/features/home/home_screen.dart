import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/nav.dart';
import '../../core/cart.dart';
import '../../core/media.dart';
import '../../core/models.dart';
import '../../core/place.dart';
import '../../core/site_chrome.dart';
import '../../core/cart_dock.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../category/category_screen.dart';
import '../shop/shop_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.seed});

  /// Fixed data instead of the network, for layout tests.
  @visibleForTesting
  final HomeData? seed;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeData? _data;
  String? _error;
  bool _loading = true;
  String? _category;
  String _query = '';
  // The "Popular near you" tab: '' is All, otherwise a category key.
  String _popularTab = '';
  int _unread = 0;
  Timer? _debounce;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.seed != null) {
      _data = widget.seed;
      _loading = false;
      return;
    }
    Place.instance.addListener(_load);
    homeSearch.addListener(_searchFromElsewhere);
    homeCategory.addListener(_categoryFromElsewhere);
    _load();
  }

  /// A category picked on another screen (the Categories page): show it here, as the website does.
  void _categoryFromElsewhere() {
    final k = homeCategory.value;
    if (k == null) return;
    homeCategory.value = null;
    _pick(k);
  }

  /// Choosing a category narrows Home to that category's shops; choosing it again, or "Clear", brings everything back.
  void _pick(String? key) {
    setState(() => _category = (key == null || key == _category) ? null : key);
    _load();
  }

  /// A search typed on another screen: show it in the box and run it.
  void _searchFromElsewhere() {
    final q = homeSearch.value;
    if (q.isEmpty) return;
    homeSearch.value = '';
    _searchController.text = q;
    _query = q;
    _load();
  }

  @override
  void dispose() {
    if (widget.seed == null) {
      Place.instance.removeListener(_load);
      homeSearch.removeListener(_searchFromElsewhere);
      homeCategory.removeListener(_categoryFromElsewhere);
    }
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = Place.instance;
      // Distances and "does not deliver" only mean something from where the customer really is. With the city default
      // the server is not given a position, so every shop is listed as orderable and nothing is wrongly crossed out.
      final d = await Api.home(lat: p.isCurrent ? p.lat : null, lng: p.isCurrent ? p.lng : null, category: _category, query: _query);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
      // The bell's badge: unread notifications, when signed in. Best effort.
      if (Api.user != null) {
        Api.notifications()
            .then((n) {
              if (mounted) setState(() => _unread = n.unread);
            })
            .catchError((_) {});
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// Shops per category label, for the "12 shops" under each tile.
  /// The website's "Trending products": the top few of each category's row, most ordered first, no repeats, fourteen at most.
  List<TrendingItem> _trendingProducts(HomeData d) {
    final all = [for (final r in d.trending) ...r.items.take(4)]..sort((a, b) => b.orders.compareTo(a.orders));
    final seen = <String>{};
    return [
      for (final t in all)
        if (seen.add(t.id)) t,
    ].take(14).toList();
  }

  Category _focusedCategory(HomeData d) {
    final all = d.catalog.isNotEmpty ? d.catalog : d.categories;
    return all.firstWhere((c) => c.key == _category, orElse: () => Category(key: _category ?? '', label: 'Shops'));
  }

  /// Which column of the tile grid the chosen category sits in, for the little pointer above the card.
  int _focusedColumn(HomeData d) {
    final all = d.catalog.isNotEmpty ? d.catalog : d.categories;
    final i = all.indexWhere((c) => c.key == _category);
    return i < 0 ? 0 : (i < 8 ? i % 4 : (i % 4));
  }

  Map<String, int> _counts(HomeData d) {
    final out = <String, int>{};
    for (final s in d.shops) {
      out[s.category] = (out[s.category] ?? 0) + 1;
    }
    return out;
  }

  bool _passes(Shop s) => true;

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final top = MediaQuery.of(context).padding.top;
    final shops = data == null ? <Shop>[] : data.shops.where(_passes).toList();
    // While typing a search the browsing sections step aside for the results.
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: top + 40,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ---- header: where to deliver, your profile, and the search -----------------------------------------------------
            AppHeader(
              unread: _unread,
              onAuthChanged: _load,
              controller: _searchController,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  _query = v;
                  _load();
                });
              },
            ),

            // ---- promos -------------------------------------------------------------------------------------------
            if (data != null && data.promos.isNotEmpty && !searching)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: _PromoStrip(promos: data.promos),
                ),
              ),

            // ---- categories: two rows of icons, the eighth is "More" --------------------------------------------------
            if (data != null && (data.catalog.isNotEmpty || data.categories.isNotEmpty) && !searching)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 41, 16, 0),
                  child: _CategoryGrid(categories: data.catalog.isNotEmpty ? data.catalog : data.categories, counts: _counts(data), selected: _category, onPick: _pick),
                ),
              ),

            // ---- a chosen category: its shops in a tinted card, with "Clear" -------------------------------------------------
            if (data != null && !searching && _category != null)
              SliverToBoxAdapter(child: _CategoryFocus(category: _focusedCategory(data), shops: shops, columnIndex: _focusedColumn(data), onClear: () => _pick(null))),

            // ---- order it again: only for someone who has ordered before (dish cards with a +) --------------------------
            if (data != null && !searching && _category == null && data.orderAgainItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Order it again', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                      ),
                      GestureDetector(
                        onTap: () => shellTab.value = tabOrders,
                        child: const Text(
                          'See all ›',
                          style: TextStyle(color: Hp.accentHi, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: data.orderAgainItems.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _ReorderCard(item: data.orderAgainItems[i]),
                  ),
                ),
              ),
            ],

            // ---- popular near you: the shops, with an All / category filter, as the website's mobile home ------------
            if (data != null && !searching && _category == null && shops.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _PopularStores(shops: shops, tab: _popularTab, onTab: (k) => setState(() => _popularTab = k)),
              ),
            ],

            // ---- search results ------------------------------------------------------------------------------------
            if (data != null && searching) ...[
              if (data.dishes.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
                    child: Text('Dishes and products', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  ),
                ),
                SliverList.builder(
                  itemCount: data.dishes.length,
                  itemBuilder: (_, i) => DishResultTile(item: data.dishes[i]),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                  child: Text('Stores matching "$_query"', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                ),
              ),
              if (shops.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(data.dishes.isEmpty ? 'Nothing matches "$_query". Try another word.' : 'No stores with that name.', textAlign: TextAlign.center)),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: shops.length,
                  itemBuilder: (_, i) => ShopCard(shop: shops[i]),
                ),
            ],

            // ---- trending products: one compact rail, as the website ------------------------------------------------------
            if (data != null && !searching && _category == null && _trendingProducts(data).isNotEmpty) SliverToBoxAdapter(child: _TrendingProducts(items: _trendingProducts(data))),
            if (!searching && _category == null) ...[
              if (_loading && data == null)
                SliverList.list(children: const [ShopSkeleton(), ShopSkeleton()])
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 40, color: Hp.muted(context)),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        FilledButton(onPressed: _load, child: const Text('Try again')),
                      ],
                    ),
                  ),
                )
              else if (data != null && shops.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 40, 16, 16),
                    child: Text('All stores', style: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    itemCount: shops.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, mainAxisExtent: 271),
                    itemBuilder: (_, i) => StoreGridCard(shop: shops[i]),
                  ),
                ),
              ],
            ],
            const SliverToBoxAdapter(child: DockSpacer(base: 28)),
          ],
        ),
      ),
    );
  }
}

/// Four across, two rows. The eighth cell is "More": it opens the whole list in place, with "Show less" at the end, as the
/// website does.
class _CategoryGrid extends StatefulWidget {
  const _CategoryGrid({required this.categories, required this.counts, this.selected, required this.onPick});
  final List<Category> categories;
  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  State<_CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<_CategoryGrid> {
  static const _cells = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.categories;
    final overflow = all.length > _cells;
    final shown = _expanded || !overflow ? all : all.take(_cells - 1).toList();
    // Always four across, as in the design: a lone category is one small tile, not one giant one.
    const columns = 4;
    return GridView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: categoryTileExtent(context, columns: columns),
      ),
      children: [
        for (final c in shown) CategoryTile(category: c, count: widget.counts[c.label], selected: widget.selected == c.key, onTap: () => widget.onPick(c.key)),
        if (overflow) _ViewAllTile(expanded: _expanded, onTap: () => setState(() => _expanded = !_expanded)),
      ],
    );
  }
}

class _ViewAllTile extends StatelessWidget {
  const _ViewAllTile({required this.onTap, this.expanded = false});
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: Hp.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Hp.line(context), width: 0.8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Column(
          children: [
            SizedBox(
              height: 30,
              child: Center(child: Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.grid_view_rounded, color: Hp.accent, size: 28)),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(expanded ? 'Show less' : 'More', maxLines: 1, style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Food near you": the chosen category's shops in a card tinted with the category's own colour.
class _CategoryFocus extends StatelessWidget {
  const _CategoryFocus({required this.category, required this.shops, required this.columnIndex, required this.onClear});
  final Category category;
  final List<Shop> shops;
  final int columnIndex;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    // Each tile is a quarter of the row less its gap; the pointer sits under the middle of the chosen one.
    final tileW = (MediaQuery.of(context).size.width - 32 - 30) / 4;
    final pointerLeft = columnIndex * (tileW + 10) + tileW / 2 - 8.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 40, height: 40, child: ColoredBox(color: Hp.surface(context), child: CachedNetworkImage(imageUrl: Media.category(category.key), fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox.shrink()))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${category.label} near you', style: const TextStyle(fontSize: 18, height: 1.55, fontWeight: FontWeight.w700, letterSpacing: -0.45)),
                  Text('${shops.length} ${shops.length == 1 ? 'store' : 'stores'}', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
                ]),
              ),
              InkWell(onTap: onClear, child: const Text('Clear', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.accent))),
            ]),
            const SizedBox(height: 16),
            if (shops.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text('No ${category.label.toLowerCase()} stores near you yet.', style: TextStyle(fontSize: 14, color: Hp.muted(context))))
            else
              GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shops.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, mainAxisExtent: 287),
                itemBuilder: (_, i) => StoreGridCard(shop: shops[i]),
              ),
          ]),
        ),
        Positioned(
          top: -8.5,
          left: pointerLeft,
          child: Transform.rotate(
            angle: 0.7853981634,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(color: Color.alphaBlend(color.withValues(alpha: 0.05), Hp.page(context)), border: Border(top: BorderSide(color: color.withValues(alpha: 0.2), width: 0.8), left: BorderSide(color: color.withValues(alpha: 0.2), width: 0.8))),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A dish the customer has ordered before: photo, name, price and a + that puts one in the cart.
class _ReorderCard extends StatelessWidget {
  const _ReorderCard({required this.item});
  final TrendingItem item;

  void _add(BuildContext context) {
    if (!item.canOrder) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(!item.shopOpen ? '${item.shopName} is closed right now.' : '${item.shopName} does not deliver to you.')));
      return;
    }
    // A dish with required choices needs them picked, which the shop page does.
    if (item.hasChoices || item.shopId.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopScreen(handle: item.shopHandle)));
      return;
    }
    HapticFeedback.selectionClick();
    Cart.instance.add(
      Shop(id: item.shopId, handle: item.shopHandle, name: item.shopName, category: ''),
      MenuItem(id: item.id, name: item.name, price: item.price, groups: const [], imageUrl: item.imageUrl, veg: item.veg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = Media.item(item.categoryKey, item.id, item.imageUrl);
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopScreen(handle: item.shopHandle))),
        child: Ink(
          decoration: BoxDecoration(
            color: Hp.surface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Hp.line(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                child: SizedBox(
                  height: 82,
                  width: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: photo,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Hp.tint(context),
                      alignment: Alignment.center,
                      child: const Text('🍽️', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 0),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 8, 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.fromPrice ? 'from ${rupees(item.price)}' : rupees(item.price),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                    ),
                    InkWell(
                      onTap: () => _add(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: item.canOrder ? Hp.accent : Hp.line(context), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.add_rounded, size: 20, color: item.canOrder ? Colors.white : Hp.muted(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoStrip extends StatefulWidget {
  const _PromoStrip({required this.promos});
  final List<Promo> promos;

  @override
  State<_PromoStrip> createState() => _PromoStripState();
}

class _PromoStripState extends State<_PromoStrip> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 114.4,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.promos.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final p = widget.promos[i];
              return Padding(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: p.imageUrl != null
                      ? CachedNetworkImage(imageUrl: p.imageUrl!, fit: BoxFit.cover, width: double.infinity)
                      : Container(
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(gradient: Hp.headerGradient),
                          alignment: Alignment.bottomLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.title,
                                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                              ),
                              if (p.subtitle != null) Text(p.subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        if (widget.promos.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.promos.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: i == _page ? Hp.accent : Hp.line(context), borderRadius: BorderRadius.circular(3)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One dish from the search: its name and price, and which shop sells it.
class DishResultTile extends StatelessWidget {
  const DishResultTile({required this.item});
  final TrendingItem item;

  @override
  Widget build(BuildContext context) {
    final muted = Hp.muted(context);
    final photo = Media.item(item.categoryKey, item.id, item.imageUrl);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Hp.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Hp.line(context)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopScreen(handle: item.shopHandle))),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(color: Hp.tint(context), borderRadius: BorderRadius.circular(16)),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: CachedNetworkImage(
                      imageUrl: photo,
                      width: 62,
                      height: 62,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Text('🍽️', style: TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.veg != null) ...[DietMark(veg: item.veg!), const SizedBox(width: 6)],
                            Expanded(
                              child: Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, height: 1.2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [item.shopName, if (!item.shopOpen) 'Closed now' else if (!item.inRange) 'Not in your area' else if (item.distanceKm != null) '${item.distanceKm} km'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: item.canOrder ? muted : Hp.bad, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(item.fromPrice ? 'from ${rupees(item.price)}' : rupees(item.price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small spaced capitals over a large bold title: the heading style of the big delivery apps.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.eyebrow, required this.title});

  /// Kept so existing call sites read the same; the design uses just the bold title.
  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) => Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.3, height: 1.15));
}

/// How the website words a shop's delivery on its card.
String _deliveryText(Shop s) {
  if (s.deliveryMode == 'self') return s.baseDeliveryFee == 0 ? 'FREE delivery' : '₹${s.baseDeliveryFee.toStringAsFixed(0)} delivery';
  return 'Delivery fee at checkout';
}

String _distanceText(double km) => km < 1 ? '${(km * 1000).round().clamp(100, 999)} m' : '${km.toStringAsFixed(1)} km';

class ShopCard extends StatelessWidget {
  const ShopCard({required this.shop});
  final Shop shop;

  static const _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final closed = !shop.open;
    final far = !shop.inRange;
    final dim = closed || far;
    final muted = Hp.muted(context);

    Widget thumb = CachedNetworkImage(
      imageUrl: Media.cover(shop.categoryKey, shop.id, shop.coverUrl),
      fit: BoxFit.cover,
      width: 92,
      height: 92,
      placeholder: (_, __) => Container(color: Hp.tint(context)),
      errorWidget: (_, __, ___) => Container(
        color: Hp.tint(context),
        alignment: Alignment.center,
        child: ShopAvatar(name: shop.name, logoUrl: shop.logoUrl, size: 48),
      ),
    );
    if (dim) thumb = ColorFiltered(colorFilter: _grey, child: thumb);

    final meta = <String>[shop.prepMinutes > 0 ? '${shop.prepMinutes}–${shop.prepMinutes + 10} mins' : 'Quick', if (shop.distanceKm != null) _distanceText(shop.distanceKm!)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Hp.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Hp.line(context)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ShopScreen(handle: shop.handle, preview: shop),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(width: 92, height: 92, child: thumb),
                        ),
                        if (shop.offerLabel != null && !dim)
                          Positioned(
                            left: 0,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
                              decoration: const BoxDecoration(
                                color: Hp.accent,
                                borderRadius: BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
                              ),
                              child: Text(
                                shop.offerLabel!,
                                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        if (dim)
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: const Color(0xFF0B0716).withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                closed ? 'Closed' : 'Too far',
                                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  shop.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            HeartButton(shopId: shop.id, size: 20),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Hp.star, size: 16),
                            const SizedBox(width: 3),
                            Text(
                              shop.ratingCount > 0 ? '${shop.rating.toStringAsFixed(1)} (${shop.ratingCount}${shop.ratingCount >= 10 ? '+' : ''})' : 'New',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(Icons.schedule_rounded, size: 14, color: muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                meta.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shop.freeDeliveryOver != null && shop.deliveryMode != 'self' ? 'Free delivery over ${rupees(shop.freeDeliveryOver!)}' : _deliveryText(shop),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _deliveryText(shop).startsWith('FREE') || shop.freeDeliveryOver != null ? Hp.ok : muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShopSkeleton extends StatelessWidget {
  const ShopSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Hp.surface(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Hp.line(context)),
        ),
        child: const Row(
          children: [
            Skeleton(height: 70, width: 70, radius: 20),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Skeleton(height: 18, width: 160), SizedBox(height: 8), Skeleton(height: 12, width: 100), SizedBox(height: 14), Skeleton(height: 24, width: 150, radius: 999)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Popular near you": a row of tabs (All and each category) over a row of shop cards, best rated first.
/// A section's heading as the website prints it: the title, and a "See all" link at the right.
class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.onSeeAll});
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ),
        if (onSeeAll != null)
          InkWell(
            onTap: onSeeAll,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Hp.accent),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 16, color: Hp.accent),
              ],
            ),
          ),
      ],
    );
  }
}

/// Greyscale, for a shop that is closed or out of range.
const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// A shop's logo in the little plate that overlaps the foot of its photo.
class _Logo extends StatelessWidget {
  const _Logo({required this.shop, required this.size, this.circle = false});
  final Shop shop;
  final double size;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final surface = Hp.surface(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: surface,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(12),
        border: Border.all(color: surface, width: 1.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: shop.logoUrl == null
          ? Center(
              child: Text(
                shop.name.isEmpty ? '?' : shop.name.characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Hp.accent),
              ),
            )
          : CachedNetworkImage(
              imageUrl: shop.logoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const Icon(Icons.storefront, color: Hp.accent),
            ),
    );
  }
}

/// "Closed" / "Too far" over a shop's photo.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.fontSize, required this.vertical, required this.horizontal, required this.alpha, required this.weight});
  final String label;
  final double fontSize;
  final double vertical;
  final double horizontal;
  final double alpha;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
    decoration: BoxDecoration(
      color: const Color(0xFF1B1046).withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: const Color(0xFFF7F5FF), fontWeight: weight, fontSize: fontSize, height: 1.33),
    ),
  );
}

/// Popular near you: the website's "All / category" chips over a row of shop cards.
class _PopularStores extends StatelessWidget {
  const _PopularStores({required this.shops, required this.tab, required this.onTab});
  final List<Shop> shops;
  final String tab;
  final ValueChanged<String> onTab;

  @override
  Widget build(BuildContext context) {
    final tabs = <String, String>{};
    for (final s in shops) {
      if (s.categoryKey.isNotEmpty) tabs.putIfAbsent(s.categoryKey, () => s.category);
    }
    final sorted = [...shops]
      ..sort((a, b) {
        if (a.inRange != b.inRange) return a.inRange ? -1 : 1;
        final r = b.rating.compareTo(a.rating);
        return r != 0 ? r : b.totalOrders.compareTo(a.totalOrders);
      });
    final shown = tab.isEmpty ? sorted : sorted.where((s) => s.categoryKey == tab).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHead(title: 'Popular near you', onSeeAll: () => shellTab.value = tabCategories),
          ),
          if (tabs.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                children: [
                  _TabChip(label: 'All', on: tab.isEmpty, onTap: () => onTab('')),
                  for (final e in tabs.entries) _TabChip(label: e.value, on: tab == e.key, onTap: () => onTab(e.key)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 11),
          SizedBox(
            height: 289,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: shown.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _PopularShopCard(shop: shown[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: on ? Hp.accent : Hp.surface(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? Hp.accent : Hp.line(context), width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: on ? Colors.white : Hp.muted(context)),
        ),
      ),
    ),
  );
}

/// A shop card of the website's "Popular near you": photo with its Closed badge and logo, name and rating, a line of what
/// it is known for, time and delivery, and a Shop now button.
class _PopularShopCard extends StatelessWidget {
  const _PopularShopCard({required this.shop});
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final faint = Hp.faint(context);
    final closed = !shop.open;
    final far = !shop.inRange;
    final dim = closed || far;
    final tags = shop.displayTags.take(3).join(' · ');
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 280,
        height: 281,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ShopScreen(handle: shop.handle, preview: shop),
            ),
          ),
          child: Ink(
            decoration: BoxDecoration(
              color: Hp.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Hp.line(context), width: 0.8),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 112,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(color: Hp.surface2(context)),
                              ColorFiltered(
                                colorFilter: dim ? _greyscale : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                                child: CachedNetworkImage(
                                  imageUrl: Media.cover(shop.categoryKey, shop.id, shop.coverUrl),
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const SizedBox.shrink(),
                                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                                ),
                              ),
                              if (dim)
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: _StatusPill(label: closed ? 'Closed' : 'Too far', fontSize: 12, vertical: 4, horizontal: 10, alpha: 0.8, weight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 24, 14, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  shop.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.star_rounded, color: Hp.star, size: 14),
                              const SizedBox(width: 2),
                              Text(shop.ratingCount > 0 ? shop.rating.toStringAsFixed(1) : 'New', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.33)),
                              if (shop.ratingCount > 0) Text(' (${shop.ratingCount})', style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 1, 14, 0),
                          child: Text(
                            tags.isEmpty ? shop.category : tags,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                          child: Container(
                            padding: const EdgeInsets.only(top: 10),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: Hp.line(context), width: 0.8)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule_rounded, size: 14, color: faint),
                                    const SizedBox(width: 4),
                                    Text(shop.prepMinutes > 0 ? '${shop.prepMinutes}–${shop.prepMinutes + 10} mins' : 'Quick', style: TextStyle(fontSize: 12, height: 1.5, color: faint)),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.two_wheeler_rounded, size: 14, color: faint),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          shop.freeDeliveryOver != null && shop.deliveryMode != 'self' ? 'Free over ${rupees(shop.freeDeliveryOver!)}' : 'Delivery fee at checkout',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 12, height: 1.5, color: faint),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: Container(
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Hp.accent.withValues(alpha: dim ? 0.55 : 1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Shop now',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                SizedBox(width: 6),
                                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(left: 14, top: 88, child: _Logo(shop: shop, size: 48, circle: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Trending products": compact cards in one row, each with its photo, name, shop, price and a +.
class _TrendingProducts extends StatelessWidget {
  const _TrendingProducts({required this.items});
  final List<TrendingItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SectionHead(title: 'Trending products', onSeeAll: () => shellTab.value = tabCategories),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _TrendingChip(item: items[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendingChip extends StatelessWidget {
  const _TrendingChip({required this.item});
  final TrendingItem item;

  void _add(BuildContext context) {
    if (!item.canOrder) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(!item.shopOpen ? '${item.shopName} is closed right now.' : '${item.shopName} does not deliver to you.')));
      return;
    }
    // A dish with required choices needs them picked, which the shop page does.
    if (item.hasChoices || item.shopId.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopScreen(handle: item.shopHandle)));
      return;
    }
    HapticFeedback.selectionClick();
    Cart.instance.add(
      Shop(id: item.shopId, handle: item.shopHandle, name: item.shopName, category: ''),
      MenuItem(id: item.id, name: item.name, price: item.price, groups: const [], imageUrl: item.imageUrl, veg: item.veg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = Media.item(item.categoryKey, item.id, item.imageUrl);
    return SizedBox(
      width: 248,
      height: 82,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopScreen(handle: item.shopHandle))),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          decoration: BoxDecoration(
            color: Hp.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Hp.line(context), width: 0.8),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ColoredBox(
                    color: Hp.surface2(context),
                    child: CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Center(child: Text('🍽️', style: TextStyle(fontSize: 24))),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      item.shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.5, color: Hp.faint(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.fromPrice ? 'from ${rupees(item.price)}' : rupees(item.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _add(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.add_rounded, size: 16, color: item.canOrder ? Hp.text(context) : Hp.faint(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A store in the two-column "All stores" grid: photo with its category badge, heart and Closed pill, then name, rating
/// and what it is known for.
class StoreGridCard extends StatelessWidget {
  const StoreGridCard({super.key, required this.shop});
  final Shop shop;

  static Color _badge(String? hex) {
    final h = (hex ?? '').replaceFirst('#', '');
    if (h.length == 6) {
      final v = int.tryParse(h, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return const Color(0xFFF97316);
  }

  @override
  Widget build(BuildContext context) {
    final faint = Hp.faint(context);
    final closed = !shop.open;
    final far = !shop.inRange;
    final dim = closed || far;
    final sub = (shop.subtitle ?? '').isNotEmpty ? shop.subtitle! : shop.category;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShopScreen(handle: shop.handle, preview: shop),
        ),
      ),
      child: Ink(
        decoration: BoxDecoration(
          color: Hp.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Hp.line(context).withValues(alpha: 0.8), width: 0.8),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 128,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: Hp.surface2(context)),
                            ColorFiltered(
                              colorFilter: dim ? _greyscale : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                              child: CachedNetworkImage(
                                imageUrl: Media.cover(shop.categoryKey, shop.id, shop.coverUrl),
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const SizedBox.shrink(),
                                errorWidget: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                            if (shop.category.isNotEmpty)
                              Positioned(
                                left: 10,
                                top: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(color: _badge(shop.categoryColor), borderRadius: BorderRadius.circular(999)),
                                  child: Text(
                                    shop.category,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13, height: 1.33),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 10,
                              top: 10,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(color: const Color(0xFF1B1046).withValues(alpha: 0.4), shape: BoxShape.circle),
                                child: Center(child: HeartButton(shopId: shop.id, size: 16)),
                              ),
                            ),
                            if (dim)
                              Positioned(
                                right: 10,
                                bottom: 60,
                                child: _StatusPill(label: closed ? 'Closed' : 'Too far', fontSize: 13, vertical: 4, horizontal: 12, alpha: 0.75, weight: FontWeight.w500),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 28, 12, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                shop.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded, color: Hp.star, size: 12),
                            const SizedBox(width: 4),
                            Text(shop.ratingCount > 0 ? shop.rating.toStringAsFixed(1) : 'New', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, height: 1.33)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                        child: Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context)),
                        ),
                      ),
                      if (shop.displayTags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final t in shop.displayTags.take(2))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(999)),
                                  child: Text(
                                    t,
                                    style: TextStyle(fontSize: 11, height: 1.5, fontWeight: FontWeight.w500, color: Hp.muted(context)),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        child: Wrap(
                          spacing: 10,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule_rounded, size: 14, color: faint),
                                const SizedBox(width: 4),
                                Text(shop.prepMinutes > 0 ? '${shop.prepMinutes} – ${shop.prepMinutes + 10} min' : 'Quick', style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
                              ],
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 138),
                              child: Text(
                                shop.freeDeliveryOver != null && shop.deliveryMode != 'self' ? 'Free over ${rupees(shop.freeDeliveryOver!)}' : 'Delivery fee at checkout',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, height: 1.33, color: faint),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(left: 12, top: 104, child: _Logo(shop: shop, size: 44)),
          ],
        ),
      ),
    );
  }
}
