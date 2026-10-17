import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/cart.dart';
import '../../core/cart_dock.dart';
import '../../core/media.dart';
import '../../core/models.dart';
import '../../core/place.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'item_sheet.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.handle, this.preview});
  final String handle;

  /// What the list already knew, shown while the menu loads.
  final Shop? preview;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

typedef _Section = ({MenuCategory category, List<MenuItem> items});

/// One row of the menu list: a section heading or a dish.
sealed class _Entry {}

class _Heading extends _Entry {
  _Heading(this.section);
  final _Section section;
}

class _Dish extends _Entry {
  _Dish(this.item);
  final MenuItem item;
}

class _ShopScreenState extends State<ShopScreen> {
  // Rows have fixed heights, so a section's place in the scroll is known exactly without building the rows before it.
  static const _headingExtent = 60.0;
  static const _dishExtent = 164.0;
  static const _chipBarExtent = 52.0;

  ShopMenu? _menu;
  String? _error;
  bool _vegOnly = false;
  String _activeId = '';

  final _scroll = ScrollController();
  final _listAnchor = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_track);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = Place.instance;
      final m = await Api.shop(widget.handle, lat: p.isCurrent ? p.lat : null, lng: p.isCurrent ? p.lng : null);
      if (mounted) setState(() => _menu = m);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String? _blockedReason(Shop shop) => shop.canOrder ? null : (!shop.open ? (shop.closedReason ?? 'This shop is closed right now.') : 'This shop does not deliver to your location.');

  /// The product page: photo, description, quantity and choices.
  Future<void> _open(Shop shop, MenuItem item) async {
    final choice = await showModalBottomSheet<ItemChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Hp.surface(context),
      barrierColor: const Color(0x660B0716),
      constraints: const BoxConstraints(maxWidth: 448),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      clipBehavior: Clip.antiAlias,
      builder: (_) => ItemSheet(item: item, categoryKey: shop.categoryKey, canOrder: shop.canOrder, blockedReason: _blockedReason(shop)),
    );
    if (choice != null) Cart.instance.add(shop, item, chosen: choice.chosen, quantity: choice.quantity);
  }

  /// The ADD button: a plain dish goes straight in; one with choices opens its page for them.
  void _add(Shop shop, MenuItem item) {
    final blocked = _blockedReason(shop);
    if (blocked != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    if (item.hasChoices) {
      _open(shop, item);
    } else {
      Cart.instance.add(shop, item);
    }
  }

  /// Items grouped under their category heading, in the shop's own order; dishes with no category go under "More".
  List<_Section> _sections(ShopMenu m) {
    bool keep(MenuItem i) => !_vegOnly || i.veg == true;
    final out = <_Section>[];
    final known = <String>{};
    for (final c in m.categories) {
      known.add(c.id);
      final items = m.items.where((i) => i.categoryId == c.id && keep(i)).toList();
      if (items.isNotEmpty) out.add((category: c, items: items));
    }
    final rest = m.items.where((i) => (i.categoryId == null || !known.contains(i.categoryId)) && keep(i)).toList();
    if (rest.isNotEmpty) out.add((category: MenuCategory(id: '_other', name: 'More'), items: rest));
    return out;
  }

  List<_Entry> _entries(List<_Section> sections) => [
        for (final s in sections) ...[_Heading(s), for (final i in s.items) _Dish(i)],
      ];

  double _extentOf(_Entry e) => e is _Heading ? _headingExtent : _dishExtent;

  /// Where each section starts, measured from the top of the list.
  Map<String, double> _starts(List<_Section> sections) {
    final out = <String, double>{};
    var y = 0.0;
    for (final s in sections) {
      out[s.category.id] = y;
      y += _headingExtent + s.items.length * _dishExtent;
    }
    return out;
  }

  /// How far below the top of the screen the list's first row currently is, in scroll terms.
  double? _listTop() {
    final ctx = _listAnchor.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !_scroll.hasClients) return null;
    return _scroll.offset + box.localToGlobal(Offset.zero).dy;
  }

  double get _pinnedHeight => MediaQuery.of(context).padding.top + _chipBarExtent;

  /// Highlights the section that is under the pinned bars, so the chips follow the scroll.
  void _track() {
    final m = _menu;
    final top = _listTop();
    if (m == null || top == null) return;
    final sections = _sections(m);
    if (sections.isEmpty) return;
    final starts = _starts(sections);
    final y = _scroll.offset + _pinnedHeight + 12 - top;
    var current = sections.first.category.id;
    for (final s in sections) {
      if (starts[s.category.id]! <= y) current = s.category.id;
    }
    if (current != _activeId && mounted) setState(() => _activeId = current);
  }

  void _jumpTo(List<_Section> sections, String id) {
    final top = _listTop();
    final start = _starts(sections)[id];
    if (top == null || start == null || !_scroll.hasClients) return;
    final target = (top + start - _pinnedHeight).clamp(0.0, _scroll.position.maxScrollExtent);
    _activeId = id;
    _scroll.animateTo(target, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    setState(() {});
  }

  /// The "Menu" button: every section with its count, tap to go there.
  void _showSections(List<_Section> sections) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: Container(
          decoration: BoxDecoration(color: Hp.surface(ctx), borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), border: Border.all(color: Hp.line(ctx), width: 0.8)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Hp.line(ctx), width: 0.8))),
                child: Row(children: [
                  const Expanded(child: Text('Menu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                  InkWell(onTap: () => Navigator.pop(ctx), customBorder: const CircleBorder(), child: SizedBox(width: 32, height: 32, child: Icon(Icons.close_rounded, size: 16, color: Hp.muted(ctx)))),
                ]),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _jumpTo(sections, sections[i].category.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: sections[i].category.id == _activeId ? Hp.tint(ctx) : null,
                            border: i == sections.length - 1 ? null : Border(bottom: BorderSide(color: Hp.line(ctx), width: 0.8)),
                          ),
                          child: Row(children: [
                            Expanded(child: Text(sections[i].category.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: sections[i].category.id == _activeId ? FontWeight.w600 : FontWeight.w500, color: sections[i].category.id == _activeId ? Hp.accentHi : null))),
                            const SizedBox(width: 12),
                            Text('${sections[i].items.length}', style: TextStyle(fontSize: 13, color: Hp.faint(ctx))),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menu = _menu;
    final shop = menu?.shop ?? widget.preview;
    final sections = menu == null ? <_Section>[] : _sections(menu);
    final entries = _entries(sections);
    final anyVeg = menu?.items.any((i) => i.veg != null) ?? false;
    final active = sections.isEmpty ? '' : (sections.any((s) => s.category.id == _activeId) ? _activeId : sections.first.category.id);

    return Scaffold(
      bottomNavigationBar: pushedNavBar(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: sections.isEmpty
          ? null
          : ValueListenableBuilder<double>(
              valueListenable: dockExtent,
              builder: (_, extent, child) => Padding(padding: EdgeInsets.only(bottom: extent), child: child),
              child: InkWell(
                onTap: () => _showSections(sections),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(color: Hp.accent, borderRadius: BorderRadius.circular(999), boxShadow: const [BoxShadow(color: Hp.glow, blurRadius: 24, offset: Offset(0, 8))]),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.restaurant_menu_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Menu', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Not floating: this page pins its own section bar, which a header coming back would sit on top of.
            AppHeader(onAuthChanged: _load, floating: false, onSubmitted: (q) => searchFromAnywhere(context, q)),
            if (_error != null)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Try again'))])))
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _BackLink(),
                    const SizedBox(height: 16),
                    if (shop != null) ...[
                      _ShopInfo(shop: shop),
                      const SizedBox(height: 24),
                      _SoldBy(name: shop.name),
                      const SizedBox(height: 24),
                      if (!shop.canOrder)
                        Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context), width: 0.8)),
                          child: Text(!shop.open ? (shop.closedReason ?? 'Closed right now') : 'This shop does not deliver to your location.', style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
                        ),
                    ],
                    if (menu == null) const _MenuSkeleton(),
                  ]),
                ),
              ),
              // What the shop is offering: a small carousel, as food apps put it under the shop's name.
              if (menu != null && menu.offers.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: _OffersCarousel(offers: menu.offers))),
              if (menu != null && sections.isEmpty && !_vegOnly)
                SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), child: Text("This store hasn't added their products yet.", style: TextStyle(fontSize: 14, color: Hp.faint(context))))),
              if (menu != null && (sections.isNotEmpty || _vegOnly)) ...[
                // The sections as chips, pinned under the header: tap to go to one; they follow you as you scroll.
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ChipBar(
                    extent: _chipBarExtent,
                    child: Container(
                      decoration: BoxDecoration(color: Hp.page(context), border: Border(bottom: BorderSide(color: Hp.line(context).withValues(alpha: 0.6), width: 0.8))),
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        children: [
                          if (anyVeg)
                            _Chip(
                              label: 'Veg only',
                              leading: const DietMark(veg: true),
                              on: _vegOnly,
                              onTap: () => setState(() => _vegOnly = !_vegOnly),
                            ),
                          for (final s in sections) _Chip(label: s.category.name, on: s.category.id == active, onTap: () => _jumpTo(sections, s.category.id)),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: SizedBox(key: _listAnchor, height: 0)),
                if (sections.isEmpty)
                  const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(48), child: Center(child: Text('No vegetarian dishes here.'))))
                else
                  SliverVariedExtentList(
                    itemExtentBuilder: (i, _) => _extentOf(entries[i]),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final e = entries[i];
                        if (e is _Heading) return _SectionHeading(name: e.section.category.name, count: e.section.items.length);
                        final item = (e as _Dish).item;
                        return _DishRow(item: item, shop: menu.shop, onOpen: () => _open(menu.shop, item), onAdd: () => _add(menu.shop, item));
                      },
                      childCount: entries.length,
                    ),
                  ),
                SliverToBoxAdapter(child: _Licences(menu: menu)),
              ],
            ],
            const SliverToBoxAdapter(child: DockSpacer(base: 112)),
          ],
        ),
      ),
    );
  }
}

class _ChipBar extends SliverPersistentHeaderDelegate {
  _ChipBar({required this.extent, required this.child});
  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  bool shouldRebuild(covariant _ChipBar old) => true;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap, this.leading});
  final String label;
  final bool on;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Hp.accent : Hp.surface(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? Hp.accent : Hp.line(context), width: 0.8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: on ? Colors.white : Hp.muted(context))),
          ]),
        ),
      ),
    );
  }
}

/// "‹ All stores", the website's way back.
class _BackLink extends StatelessWidget {
  const _BackLink();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.arrow_back_rounded, size: 16, color: Hp.muted(context)),
          const SizedBox(width: 6),
          Text('All stores', style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
        ]),
      ),
    );
  }
}

/// The shop's card: logo, name (with Closed), what it sells, a line about it, its tags, rating, time and delivery.
class _ShopInfo extends StatelessWidget {
  const _ShopInfo({required this.shop});
  final Shop shop;

  String get _delivery {
    if (shop.deliveryMode == 'self') return shop.baseDeliveryFee == 0 ? 'FREE delivery' : '₹${shop.baseDeliveryFee.toStringAsFixed(0)} delivery';
    return 'Delivery fee at checkout';
  }

  @override
  Widget build(BuildContext context) {
    final faint = Hp.faint(context);
    final sub = (shop.subtitle ?? '').isNotEmpty ? shop.subtitle! : shop.category;
    final logo = shop.logoUrl ?? Media.cover(shop.categoryKey, shop.id, shop.coverUrl);
    final about = (shop.description ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context).withValues(alpha: 0.8), width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(imageUrl: logo, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.storefront, color: Hp.accent)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(shop.name, style: const TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                if (!shop.open)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Hp.bad.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                    child: const Text('Closed', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: Hp.bad)),
                  ),
              ]),
              const SizedBox(height: 2),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
              if (shop.displayTags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final t in shop.displayTags)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(999)),
                      child: Text(t, style: TextStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w500, color: Hp.muted(context))),
                    ),
                ]),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, size: 14, color: Hp.star),
                  const SizedBox(width: 4),
                  Text(shop.rating > 0 ? shop.rating.toStringAsFixed(1) : 'New', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: Hp.text(context))),
                  if (shop.ratingCount > 0) Text(' (${shop.ratingCount})', style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
                ]),
                if (shop.prepMinutes > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule_rounded, size: 14, color: faint),
                    const SizedBox(width: 4),
                    Text('${shop.prepMinutes} – ${shop.prepMinutes + 10} min', style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
                  ]),
                Text(_delivery, style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
              ]),
            ]),
          ),
        ]),
        if (about.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(height: 0.8, color: Hp.line(context)),
          const SizedBox(height: 12),
          Text(about, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.45, color: Hp.muted(context))),
        ],
        if ((shop.addressLine ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.location_on_outlined, size: 14, color: faint)),
            const SizedBox(width: 6),
            Expanded(child: Text(shop.addressLine!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.4, color: faint))),
          ]),
        ],
      ]),
    );
  }
}

/// "Sold by X. Hyperpik lists this store and collects payment on their behalf." as the website says it.
class _SoldBy extends StatelessWidget {
  const _SoldBy({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final muted = Hp.muted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: Hp.line(context), width: 0.8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.storefront_outlined, size: 14, color: Hp.faint(context))),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(style: TextStyle(fontSize: 13, height: 1.33, color: muted), children: [
              const TextSpan(text: 'Sold by '),
              TextSpan(text: name, style: TextStyle(fontWeight: FontWeight.w600, color: Hp.text(context))),
              const TextSpan(text: '. Hyperpik lists this store and collects payment on their behalf.'),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Skeleton(height: 20, width: 140),
      const SizedBox(height: 16),
      for (var i = 0; i < 3; i++)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(height: 16, width: 160), SizedBox(height: 10), Skeleton(height: 14, width: 60), SizedBox(height: 10), Skeleton(height: 12, width: 200)])),
            SizedBox(width: 16),
            Skeleton(height: 112, width: 112, radius: 16),
          ]),
        ),
    ]);
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.name, required this.count});
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w800, letterSpacing: -0.3))),
        const SizedBox(width: 8),
        Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('$count', style: TextStyle(fontSize: 13, height: 1.3, color: Hp.faint(context)))),
      ]),
    );
  }
}

/// A dish the way food apps list it: its name, price and description on the left, a photo on the right with ADD on its foot.
class _DishRow extends StatelessWidget {
  const _DishRow({required this.item, required this.shop, required this.onOpen, required this.onAdd});
  final MenuItem item;
  final Shop shop;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final photo = Media.item(shop.categoryKey, item.id, item.imageUrl);
    final price = item.fromPrice;
    final muted = Hp.muted(context);
    final desc = (item.description ?? '').trim();
    return InkWell(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Hp.line(context).withValues(alpha: 0.7), width: 0.8))),
        child: Opacity(
          opacity: item.available ? 1 : 0.55,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (item.veg != null) ...[DietMark(veg: item.veg!), const SizedBox(width: 8)],
                    if (item.bestseller)
                      Row(children: [
                        const Icon(Icons.local_fire_department_rounded, size: 14, color: Hp.star),
                        const SizedBox(width: 2),
                        Text('Bestseller', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Hp.star)),
                      ]),
                  ]),
                  const SizedBox(height: 6),
                  Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(price > 0 ? (item.needsChoice ? 'from ${rupees(price)}' : rupees(price)) : 'Price on selection', style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(desc, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.4, color: muted)),
                  ],
                  if (!item.available && item.unavailableLabel != null)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.unavailableLabel!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Hp.bad))),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 112,
              height: 132,
              child: Stack(clipBehavior: Clip.none, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 112,
                    height: 112,
                    child: ColoredBox(color: Hp.surface2(context), child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Center(child: Text('🍽️', style: TextStyle(fontSize: 30))))),
                  ),
                ),
                Positioned(bottom: 0, left: 8, right: 8, child: _AddControl(item: item, shop: shop, onAdd: onAdd)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ADD, or the stepper once the dish is in the bag.
class _AddControl extends StatelessWidget {
  const _AddControl({required this.item, required this.shop, required this.onAdd});
  final MenuItem item;
  final Shop shop;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Cart.instance,
      builder: (context, _) {
        final q = Cart.instance.quantityOf(shop.id, item.id);
        final enabled = item.available;
        if (q == 0 || !enabled) {
          return InkWell(
            onTap: enabled ? onAdd : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Hp.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: enabled && shop.canOrder ? Hp.accent : Hp.lineStrong(context), width: 1),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(enabled ? 'ADD' : 'N/A', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: enabled && shop.canOrder ? Hp.accent : Hp.faint(context))),
                if (enabled && item.hasChoices) ...[const SizedBox(width: 2), Icon(Icons.add_rounded, size: 14, color: shop.canOrder ? Hp.accent : Hp.faint(context))],
              ]),
            ),
          );
        }
        final lines = Cart.instance.cartFor(shop.id)?.lines.where((l) => l.itemId == item.id).toList() ?? const <CartLine>[];
        return Container(
          height: 36,
          decoration: BoxDecoration(color: Hp.accent, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))]),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            InkWell(
              onTap: lines.isEmpty ? null : () => Cart.instance.setQuantity(shop.id, lines.last, lines.last.quantity - 1),
              child: const SizedBox(width: 32, height: 36, child: Icon(Icons.remove_rounded, size: 18, color: Colors.white)),
            ),
            Text('$q', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            InkWell(onTap: onAdd, child: const SizedBox(width: 32, height: 36, child: Icon(Icons.add_rounded, size: 18, color: Colors.white))),
          ]),
        );
      },
    );
  }
}

/// Who the customer is buying from: the licences Hyperpik has checked, and the shop's tax registration.
class _Licences extends StatelessWidget {
  const _Licences({required this.menu});
  final ShopMenu menu;

  @override
  Widget build(BuildContext context) {
    final muted = Hp.muted(context);
    final faint = Hp.faint(context);
    final shop = menu.shop;
    Widget row(IconData icon, Color color, String title, String sub) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600)),
                Text(sub, style: TextStyle(fontSize: 13, height: 1.4, color: muted)),
              ]),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: cardDecoration(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.verified_user_outlined, size: 18, color: Hp.accent), SizedBox(width: 8), Text('Licences & registrations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))]),
          const SizedBox(height: 2),
          Text('Checked by Hyperpik before ${shop.name} could sell here.', style: TextStyle(fontSize: 13, height: 1.4, color: faint)),
          if (menu.licences.isEmpty && menu.gstin == null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text("This shop's licence details have not been added yet.", style: TextStyle(fontSize: 13, color: muted))),
          for (final l in menu.licences)
            row(Icons.verified_rounded, Hp.ok, l.label, l.validUntil == null ? 'Verified by Hyperpik' : 'Verified by Hyperpik · valid until ${DateFormat('d MMM yyyy').format(l.validUntil!)}'),
          if (menu.gstin != null) row(Icons.receipt_long_outlined, Hp.accent, 'GSTIN ${menu.gstin}', 'Tax registration of the seller'),
          if ((shop.addressLine ?? '').isNotEmpty) row(Icons.storefront_outlined, muted, shop.name, shop.addressLine!),
        ]),
      ),
    );
  }
}

/// The shop's running offers as a row of cards you swipe through, with a dot for each.
class _OffersCarousel extends StatefulWidget {
  const _OffersCarousel({required this.offers});
  final List<ShopOffer> offers;

  @override
  State<_OffersCarousel> createState() => _OffersCarouselState();
}

class _OffersCarouselState extends State<_OffersCarousel> {
  final _controller = PageController(viewportFraction: 0.86);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offers = widget.offers;
    return Column(children: [
      SizedBox(
        height: 76,
        child: PageView.builder(
          controller: _controller,
          itemCount: offers.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) {
            final o = offers[i];
            final detail = o.code != null
                ? 'Use code ${o.code}'
                : o.minOrder > 0
                    ? 'On orders above ${rupees(o.minOrder)}'
                    : ((o.subtitle ?? '').isNotEmpty ? o.subtitle! : 'On selected items');
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 16 : 4, right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFF3B1AA0), Color(0xFF1C1240)]),
                  border: Border.all(color: Hp.accentHi.withValues(alpha: 0.35), width: 0.8),
                ),
                child: Row(children: [
                  const Icon(Icons.local_offer_rounded, color: Color(0xFFC9B8FF), size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFD9CCFF), fontWeight: FontWeight.w800, fontSize: 17, height: 1.2)),
                      const SizedBox(height: 2),
                      Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8))),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      if (offers.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < offers.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 16 : 6,
                height: 5,
                decoration: BoxDecoration(color: i == _page ? Hp.accent : Hp.line(context), borderRadius: BorderRadius.circular(3)),
              ),
          ]),
        ),
    ]);
  }
}
