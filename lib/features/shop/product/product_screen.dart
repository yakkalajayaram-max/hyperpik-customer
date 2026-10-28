import 'package:flutter/material.dart';

import '../../../core/cart.dart';
import '../../../core/cart_dock.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../cart/cart_screen.dart';
import 'product_ctl.dart';
import 'product_parts.dart';

/// The product page. One screen, four arrangements chosen by what the shop sells, each taken from the shopping app people
/// already know how to use for that:
///
///   clothes, jewellery, sport     Myntra:  a tall photo with 1/5 counter, brand over name, price with MRP and % OFF, round
///                                          size buttons and a size chart, best offers, details, "Add to bag"
///   electronics, home, furniture  Amazon:  white photo stage with thumbnails, star rating, M.R.P. and discount, stock and
///                                          delivery lines, variant cards, About this item, specifications, in the box,
///                                          "Add to cart" and "Buy now"
///   food                          Zomato:  a big dish photo, veg mark, bestseller flag, "customise" rows, a quantity stepper
///                                          and "Add item"
///   groceries, fresh, medicine,
///   everything else               Blinkit: a square pack photo, pack-size cards with per-100 g price, a saving line,
///                                          highlights, details and "Add to basket"
///
/// What every arrangement shows comes from the same place (ProductCtl, product_parts.dart): the facts a shop filled in, its
/// choices, its price. Only the arrangement differs, so a size can never be required on one page and optional on another.
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.item, required this.menu, required this.canOrder, this.blockedReason});
  final MenuItem item;
  final ShopMenu menu;
  final bool canOrder;
  final String? blockedReason;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> with HidesCartDock {
  late final ProductCtl ctl = ProductCtl(item: widget.item, shop: widget.menu.shop, canOrder: widget.canOrder, blockedReason: widget.blockedReason);

  Shop get shop => widget.menu.shop;
  MenuItem get item => widget.item;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _add({bool buyNow = false}) {
    final choice = ctl.submit(buyNow: buyNow);
    if (choice == null) return;
    Cart.instance.add(shop, item, chosen: choice.chosen, quantity: choice.quantity);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    nav.pop();
    if (buyNow) {
      nav.push(MaterialPageRoute<void>(builder: (_) => CartScreen(shopId: shop.id)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text('${item.name} added'), duration: const Duration(seconds: 2)));
    }
  }

  void _openOther(MenuItem other) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProductScreen(item: other, menu: widget.menu, canOrder: widget.canOrder, blockedReason: widget.blockedReason)));
  }

  /// Other things this shop sells, the same kind first.
  List<MenuItem> get _related {
    final same = widget.menu.items.where((i) => i.id != item.id && i.available && i.categoryId == item.categoryId).toList();
    final rest = widget.menu.items.where((i) => i.id != item.id && i.available && i.categoryId != item.categoryId).toList();
    return [...same, ...rest].take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        switch (shop.productLayout) {
          case 'apparel':
            return _Apparel(s: this);
          case 'electronics':
            return _Electronics(s: this);
          case 'food':
            return _Food(s: this);
          default:
            return _Grocery(s: this);
        }
      },
    );
  }
}

typedef _S = _ProductScreenState;

/// The name, price, MRP and "% OFF" as a block, sized for the layout.
class _PriceBlock extends StatelessWidget {
  const _PriceBlock({required this.ctl, this.big = 24, this.offColor = const Color(0xFFE11D48), this.note = true, this.fromWhenChoices = true});
  final ProductCtl ctl;
  final double big;
  final Color offColor;
  final bool note;
  final bool fromWhenChoices;

  @override
  Widget build(BuildContext context) {
    final item = ctl.item;
    final priced = item.price <= 0 && item.hasChoices;
    final shown = priced ? (ctl.chosen.isEmpty ? item.fromPrice : ctl.unit) : ctl.unit;
    final mrp = ctl.mrp;
    final off = ctl.discountPercent;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 2, children: [
        if (priced && ctl.chosen.isEmpty && fromWhenChoices) Text('From', style: TextStyle(fontSize: big * 0.55, color: Hp.muted(context), fontWeight: FontWeight.w600)),
        Text(rs(shown), style: TextStyle(fontSize: big, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15)),
        if (mrp != null) Text(rs(mrp), style: TextStyle(fontSize: big * 0.6, color: Hp.faint(context), decoration: TextDecoration.lineThrough)),
        if (off != null) Text('$off% OFF', style: TextStyle(fontSize: big * 0.58, fontWeight: FontWeight.w800, color: offColor)),
      ]),
      if (note) Padding(padding: const EdgeInsets.only(top: 2), child: Text('Inclusive of all taxes', style: TextStyle(fontSize: 11.5, color: Hp.faint(context), fontWeight: FontWeight.w600))),
    ]);
  }
}

/// The photo header's floating back button, above the status bar.
class _Back extends StatelessWidget {
  const _Back();
  @override
  Widget build(BuildContext context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        child: RoundIcon(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.of(context).maybePop()),
      );
}

Widget _stateNote(ProductCtl ctl) {
  if (ctl.item.available && ctl.canOrder) return const SizedBox.shrink();
  final text = !ctl.canOrder ? (ctl.blockedReason ?? 'Not available right now') : (ctl.item.unavailableLabel ?? 'Out of stock');
  return Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Hp.bad.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [const Icon(Icons.info_outline_rounded, size: 17, color: Hp.bad), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Hp.bad)))]),
  );
}

// =============================================================================================================== apparel

class _Apparel extends StatelessWidget {
  const _Apparel({required this.s});
  final _S s;

  @override
  Widget build(BuildContext context) {
    final ctl = s.ctl;
    final item = s.item;
    final shop = s.shop;
    final p = item.product;
    final brand = p?.brand ?? shop.name;
    final chart = p?.sections.where((x) => x.key == 'size_chart').firstOrNull;
    return Scaffold(
      backgroundColor: Hp.page(context),
      body: Stack(children: [
        ListView(padding: EdgeInsets.zero, children: [
          PhotoPager(
            photos: productPhotos(item, shop.categoryKey),
            aspect: 0.82,
            counter: true,
            onBadge: RatingPill(rating: shop.rating, count: shop.ratingCount, onImage: true),
          ),
          Band(
            top: 0,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(brand, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(item.name, style: TextStyle(fontSize: 15, color: Hp.muted(context), height: 1.3)),
              const SizedBox(height: 12),
              _PriceBlock(ctl: ctl, big: 22, fromWhenChoices: false),
              if (productTags(item).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(spacing: 6, runSpacing: 6, children: productTags(item))),
              _stateNote(ctl),
            ]),
          ),
          if (ctl.groups.isNotEmpty)
            Band(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final g in ctl.groups) ...[
                  Row(children: [
                    Expanded(child: ChoiceBlock(ctl: ctl, group: g, style: g.isVariation ? ChoiceStyle.chips : ChoiceStyle.rows, heading: g.isVariation && g.name.toLowerCase().contains('size') ? 'Select size' : null)),
                  ]),
                  if (g.isVariation && g.name.toLowerCase().contains('size') && chart != null && (chart.text ?? '').isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14, top: 0),
                        child: TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          onPressed: () => _sizeChart(context, chart),
                          icon: const Icon(Icons.straighten_rounded, size: 17),
                          label: const Text('Size chart', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                ],
              ]),
            ),
          Band(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const BlockTitle('Delivery'), ...deliveryLines(shop, item), if ((p?.sections.any((x) => x.key == 'return_policy') ?? false)) InfoLine(Icons.assignment_return_outlined, p!.sections.firstWhere((x) => x.key == 'return_policy').text ?? '')])),
          if (s.widget.menu.offers.isNotEmpty) Band(child: OffersBand(offers: s.widget.menu.offers)),
          Band(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BlockTitle('Product details'),
              if ((item.description ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: DescriptionText(text: item.description!)),
              DetailSections(item: item, skip: const {'size_chart', 'return_policy'}, accordion: false),
            ]),
          ),
          Band(padding: const EdgeInsets.symmetric(vertical: 16), child: RelatedRow(items: s._related, shop: shop, onOpen: s._openOther, title: 'More from ${shop.name}', tall: true)),
          SizedBox(height: 100 + MediaQuery.of(context).padding.bottom),
        ]),
        const _Back(),
      ]),
      bottomNavigationBar: BottomBar(error: ctl.error, children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: ctl.soldOut ? null : () => s._add(),
            icon: const Icon(Icons.shopping_bag_outlined, size: 20),
            label: Text(ctl.ready || ctl.soldOut ? (ctl.soldOut ? ctl.buttonLabel('') : 'ADD TO BAG · ${rs(ctl.total)}') : ctl.buttonLabel('').toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4)),
          ),
        ),
      ]),
    );
  }

  void _sizeChart(BuildContext context, DetailSection chart) {
    final rows = (chart.text ?? '').split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Hp.surface(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Expanded(child: Text('Size chart', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))]),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [
                  for (var k = 0; k < rows.length; k++)
                    Container(
                      width: double.infinity,
                      color: k.isEven ? Hp.surface2(context) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      child: Text(rows[k], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ======================================================================================================== electronics

class _Electronics extends StatelessWidget {
  const _Electronics({required this.s});
  final _S s;

  @override
  Widget build(BuildContext context) {
    final ctl = s.ctl;
    final item = s.item;
    final shop = s.shop;
    final p = item.product;
    final inBox = p?.sections.where((x) => x.key == 'in_the_box').firstOrNull;
    final specs = p?.sections.where((x) => x.key == 'key_specs').firstOrNull;
    final off = ctl.discountPercent;
    final stockLine = !item.available
        ? (item.unavailableLabel ?? 'Currently unavailable')
        : (p?.lowStock != null ? 'Only ${p!.lowStock} left in stock' : 'In stock');
    final stockColor = !item.available ? Hp.bad : (p?.lowStock != null ? const Color(0xFFB45309) : const Color(0xFF15803D));
    return Scaffold(
      backgroundColor: Hp.page(context),
      appBar: AppBar(
        backgroundColor: Hp.surface(context),
        scrolledUnderElevation: 1,
        title: Text(shop.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: ListView(padding: EdgeInsets.zero, children: [
        Band(
          top: 0,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Visit the ${p?.brand ?? shop.name} store', style: TextStyle(fontSize: 12.5, color: Hp.accent, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(item.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3)),
            const SizedBox(height: 6),
            StarRow(rating: shop.rating, count: shop.ratingCount),
          ]),
        ),
        Container(
          color: Colors.white,
          child: PhotoPager(photos: productPhotos(item, shop.categoryKey), aspect: 1.05, contain: true, thumbs: true),
        ),
        Band(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (off != null)
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text('-$off%', style: const TextStyle(fontSize: 26, color: Color(0xFFCC0C39), fontWeight: FontWeight.w400)),
                const SizedBox(width: 10),
                Text(rs(ctl.item.price), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.1)),
              ])
            else
              _PriceBlock(ctl: ctl, big: 28, note: false),
            if (ctl.mrp != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: Hp.muted(context)), children: [const TextSpan(text: 'M.R.P.: '), TextSpan(text: rs(ctl.mrp!), style: const TextStyle(decoration: TextDecoration.lineThrough))]))),
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('Inclusive of all taxes', style: TextStyle(fontSize: 12, color: Hp.muted(context)))),
            const SizedBox(height: 10),
            Text(stockLine, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: stockColor)),
            const SizedBox(height: 6),
            ...deliveryLines(shop, item),
            _stateNote(ctl),
            const SizedBox(height: 10),
            _TrustRow(item: item, shop: shop),
          ]),
        ),
        if (ctl.groups.isNotEmpty)
          Band(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final g in ctl.groups) ChoiceBlock(ctl: ctl, group: g, style: g.isVariation ? ChoiceStyle.cards : ChoiceStyle.rows)])),
        if (s.widget.menu.offers.isNotEmpty) Band(child: OffersBand(offers: s.widget.menu.offers)),
        if ((item.description ?? '').isNotEmpty)
          Band(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const BlockTitle('About this item'), DescriptionText(text: item.description!, bullets: true)])),
        if (specs != null && specs.specs.isNotEmpty) Band(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const BlockTitle('Technical details'), SpecTable(rows: specs.specs)])),
        if (inBox != null && (inBox.text ?? '').isNotEmpty) Band(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const BlockTitle("What's in the box"), DescriptionText(text: inBox.text!.replaceAll(RegExp(r'\s*,\s*'), '\n'), bullets: true)])),
        Band(child: DetailSections(item: item, skip: const {'key_specs', 'in_the_box'}, accordion: false)),
        Band(padding: const EdgeInsets.symmetric(vertical: 16), child: RelatedRow(items: s._related, shop: shop, onOpen: s._openOther, title: 'More from ${shop.name}')),
        SizedBox(height: 110 + MediaQuery.of(context).padding.bottom),
      ]),
      bottomNavigationBar: BottomBar(error: ctl.error, children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: const Color(0xFFFFD814), foregroundColor: Colors.black, shape: const StadiumBorder()),
            onPressed: ctl.soldOut ? null : () => s._add(),
            child: Text(ctl.soldOut || !ctl.ready ? ctl.buttonLabel('') : 'Add to cart', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: const Color(0xFFFFA41C), foregroundColor: Colors.black, shape: const StadiumBorder()),
            onPressed: ctl.soldOut ? null : () => s._add(buyNow: true),
            child: const Text('Buy now', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

/// Amazon's row of small reassurances: only the ones this product can honestly claim.
class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.item, required this.shop});
  final MenuItem item;
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    final items = <(IconData, String)>[
      if (p?.warrantyMonths != null) (Icons.verified_user_outlined, '${p!.warrantyMonths! % 12 == 0 ? '${p.warrantyMonths! ~/ 12} year' : '${p.warrantyMonths} month'} warranty'),
      if (p?.trackSerials ?? false) (Icons.confirmation_number_outlined, 'Serial no. on bill'),
      if (shop.supportsDelivery) (Icons.local_shipping_outlined, 'Home delivery'),
      (Icons.lock_outline_rounded, 'Secure payment'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in items)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Column(children: [
              Icon(e.$1, size: 26, color: Hp.accent),
              const SizedBox(height: 4),
              SizedBox(width: 74, child: Text(e.$2, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Hp.accent, fontWeight: FontWeight.w600, height: 1.2))),
            ]),
          ),
      ]),
    );
  }
}

// ============================================================================================================== food

class _Food extends StatelessWidget {
  const _Food({required this.s});
  final _S s;

  @override
  Widget build(BuildContext context) {
    final ctl = s.ctl;
    final item = s.item;
    final shop = s.shop;
    final p = item.product;
    final meta = <Widget>[
      if (item.bestseller) const TagChip('Bestseller', tone: 'warn', icon: Icons.local_fire_department_rounded),
      if ((p?.prepMinutes ?? 0) > 0) TagChip('${p!.prepMinutes} min', icon: Icons.schedule_rounded),
      if ((item.portion ?? '').isNotEmpty) TagChip(item.portion!, icon: Icons.restaurant_rounded),
      ...productTags(item).where((t) => true),
    ];
    final info = DetailSections(item: item, accordion: true, includeFacts: false);
    return Scaffold(
      backgroundColor: Hp.surface(context),
      body: Stack(children: [
        ListView(padding: EdgeInsets.zero, children: [
          SizedBox(
            height: 290,
            child: Stack(fit: StackFit.expand, children: [
              PhotoPager(photos: productPhotos(item, shop.categoryKey), aspect: 1.4),
              Positioned(left: 0, right: 0, bottom: 0, height: 80, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent])))),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -22),
            child: Container(
              decoration: BoxDecoration(color: Hp.surface(context), borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (item.veg != null) Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: DietMark(veg: item.veg!)),
                  Expanded(child: Text(item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.25))),
                ]),
                const SizedBox(height: 8),
                _PriceBlock(ctl: ctl, big: 20, offColor: const Color(0xFF16A34A), note: false),
                if (meta.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(spacing: 6, runSpacing: 6, children: meta)),
                if ((item.description ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: DescriptionText(text: item.description!)),
                _stateNote(ctl),
                if (ctl.groups.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(height: 1, color: Hp.line(context)),
                  const SizedBox(height: 16),
                  const Text('Customise as per your taste', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  for (final g in ctl.groups) ChoiceBlock(ctl: ctl, group: g),
                ],
                if (info is! SizedBox) ...[Container(height: 1, color: Hp.line(context)), info],
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.storefront_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text('From ${shop.name}', style: TextStyle(fontSize: 13, color: Hp.muted(context), fontWeight: FontWeight.w600))),
                  RatingPill(rating: shop.rating, count: shop.ratingCount),
                ]),
                const SizedBox(height: 18),
              ]),
            ),
          ),
          Container(color: Hp.page(context), padding: const EdgeInsets.symmetric(vertical: 16), child: RelatedRow(items: s._related, shop: shop, onOpen: s._openOther, title: 'You may also like', card: 138)),
          SizedBox(height: 90 + MediaQuery.of(context).padding.bottom),
        ]),
        const _Back(),
      ]),
      bottomNavigationBar: BottomBar(error: ctl.error, children: [
        if (!ctl.soldOut) ...[QtyStepper(ctl: ctl), const SizedBox(width: 12)],
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: const Color(0xFFE23744), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: ctl.soldOut ? null : () => s._add(),
            child: Text(ctl.buttonLabel('Add item'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

// ========================================================================================================== grocery etc.

class _Grocery extends StatelessWidget {
  const _Grocery({required this.s});
  final _S s;

  @override
  Widget build(BuildContext context) {
    final ctl = s.ctl;
    final item = s.item;
    final shop = s.shop;
    final p = item.product;
    final unitPrice = perUnitLabel(item.price > 0 ? item.price : ctl.unit, item.portion, p?.soldByWeight ?? false, p?.unit);
    final saving = ctl.mrp == null ? null : ctl.mrp! - item.price;
    final rx = p?.badges.any((b) => b.key == 'rx') ?? false;
    final shelf = p?.sections.where((x) => x.key == 'shelf_life').firstOrNull?.text;
    return Scaffold(
      backgroundColor: Hp.page(context),
      appBar: AppBar(
        backgroundColor: Hp.surface(context),
        scrolledUnderElevation: 1,
        title: Text(shop.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: ListView(padding: EdgeInsets.zero, children: [
        Container(color: Colors.white, child: PhotoPager(photos: productPhotos(item, shop.categoryKey), aspect: 1.15, contain: true)),
        Band(
          top: 0,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p?.brand != null) Text(p!.brand!.toUpperCase(), style: TextStyle(fontSize: 11.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: Hp.accent)),
            const SizedBox(height: 3),
            Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.3)),
            if ((item.portion ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.portion!, style: TextStyle(fontSize: 13.5, color: Hp.muted(context), fontWeight: FontWeight.w600))),
            const SizedBox(height: 12),
            _PriceBlock(ctl: ctl, big: 22, offColor: const Color(0xFF16A34A)),
            if (saving != null && saving > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('You save ${rs(saving)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF15803D)))),
            if (unitPrice != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(unitPrice, style: TextStyle(fontSize: 12.5, color: Hp.muted(context), fontWeight: FontWeight.w600))),
            if (productTags(item).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(spacing: 6, runSpacing: 6, children: productTags(item))),
            _stateNote(ctl),
          ]),
        ),
        if (rx)
          Band(
            child: Row(children: [
              const Icon(Icons.medication_outlined, color: Hp.bad),
              const SizedBox(width: 10),
              Expanded(child: Text('This medicine needs a valid prescription from a registered doctor.', style: TextStyle(fontSize: 13.5, height: 1.4, color: Hp.text(context), fontWeight: FontWeight.w600))),
            ]),
          ),
        if (ctl.groups.isNotEmpty) Band(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final g in ctl.groups) ChoiceBlock(ctl: ctl, group: g, style: g.isVariation ? ChoiceStyle.cards : ChoiceStyle.rows, heading: g.isVariation ? 'Select ${g.name.toLowerCase()}' : null)])),
        Band(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const BlockTitle('Delivery'),
          ...deliveryLines(shop, item),
          if (shelf != null && shelf.isNotEmpty) InfoLine(Icons.event_available_outlined, 'Shelf life: $shelf'),
          if (p?.earliestExpiry != null) InfoLine(Icons.event_outlined, 'Expiry from ${p!.earliestExpiry}'),
        ])),
        if (s.widget.menu.offers.isNotEmpty) Band(child: OffersBand(offers: s.widget.menu.offers)),
        if ((item.description ?? '').isNotEmpty || (p != null && (p.sections.isNotEmpty || p.rows.isNotEmpty || p.brand != null)))
          Band(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((item.description ?? '').isNotEmpty) ...[const BlockTitle('About this product'), DescriptionText(text: item.description!), const SizedBox(height: 8)],
              DetailSections(item: item, skip: const {'shelf_life'}),
            ]),
          ),
        Band(padding: const EdgeInsets.symmetric(vertical: 16), child: RelatedRow(items: s._related, shop: shop, onOpen: s._openOther, title: 'You might also need')),
        SizedBox(height: 100 + MediaQuery.of(context).padding.bottom),
      ]),
      bottomNavigationBar: BottomBar(error: ctl.error, children: [
        if (!ctl.soldOut) ...[QtyStepper(ctl: ctl), const SizedBox(width: 12)],
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: ctl.soldOut ? null : () => s._add(),
            child: Text(ctl.buttonLabel('Add to basket'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}
