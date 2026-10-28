import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/media.dart';
import '../../../core/models.dart';
import '../../../core/theme.dart';
import 'product_ctl.dart';

/// Pieces every product layout is built from, so the apparel, electronics, food and grocery pages differ in arrangement and
/// feel while the facts, the rules and the wording stay the same.

final _rs = NumberFormat.decimalPattern('en_IN');

/// "₹1,299".
String rs(num v) => '₹${_rs.format(v.round())}';

/// "₹45 per 100 g" from a price and a pack size such as "500 g" or "1 kg"; null when the size is not a plain measure.
String? perUnitLabel(num price, String? packSize, bool byWeight, String? unit) {
  if (price <= 0) return null;
  if (byWeight) return unit == null || unit.isEmpty ? null : 'per $unit';
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(kg|g|gm|l|ltr|ml)$', caseSensitive: false).firstMatch((packSize ?? '').trim());
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  final u = m.group(2)!.toLowerCase();
  if (n <= 0) return null;
  final base = (u == 'kg' || u == 'l' || u == 'ltr') ? n * 1000 : n;
  final liquid = u == 'l' || u == 'ltr' || u == 'ml';
  final per100 = price / base * 100;
  return '₹${per100 < 10 ? per100.toStringAsFixed(2) : per100.round()} per 100 ${liquid ? 'ml' : 'g'}';
}

/// The photos of an item: its main photo, then the extra ones, or the category's stock photo when it has none.
List<String> productPhotos(MenuItem item, String categoryKey) {
  final main = (item.imageUrl ?? '').trim();
  final extra = (item.product?.gallery ?? const <String>[]).where((u) => u.trim().isNotEmpty).toList();
  final all = [if (main.isNotEmpty) main, ...extra];
  return all.isEmpty ? [Media.item(categoryKey, item.id)] : all;
}

/// A round button over a photo (back, close).
class RoundIcon extends StatelessWidget {
  const RoundIcon({super.key, required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Hp.surface(context).withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 1.5,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(message: tooltip ?? '', child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: Hp.text(context)))),
      ),
    );
  }
}

/// A swipeable set of photos. [counter] draws "2/5" (Myntra); otherwise dots. [contain] shows the whole product on a plain
/// ground (electronics) instead of filling the frame (clothes, food).
class PhotoPager extends StatefulWidget {
  const PhotoPager({super.key, required this.photos, this.aspect = 1, this.contain = false, this.counter = false, this.thumbs = false, this.onBadge, this.overlay});
  final List<String> photos;
  final double aspect;
  final bool contain;
  final bool counter;
  final bool thumbs;

  /// Something drawn at the bottom-left of the photo (a rating chip, a discount flag).
  final Widget? onBadge;
  final Widget? overlay;

  @override
  State<PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<PhotoPager> {
  final _c = PageController();
  int _i = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _img(String url) => CachedNetworkImage(
        imageUrl: url,
        fit: widget.contain ? BoxFit.contain : BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, __) => ColoredBox(color: Hp.surface2(context)),
        errorWidget: (_, __, ___) => ColoredBox(color: Hp.surface2(context), child: Icon(Icons.image_not_supported_outlined, color: Hp.faint(context))),
      );

  @override
  Widget build(BuildContext context) {
    final n = widget.photos.length;
    final ground = widget.contain ? Colors.white : Hp.surface2(context);
    return Column(children: [
      AspectRatio(
        aspectRatio: widget.aspect,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(color: ground),
          PageView.builder(
            controller: _c,
            itemCount: n,
            onPageChanged: (v) => setState(() => _i = v),
            itemBuilder: (_, k) => Padding(padding: EdgeInsets.all(widget.contain ? 18 : 0), child: _img(widget.photos[k])),
          ),
          if (widget.overlay != null) widget.overlay!,
          if (widget.onBadge != null) Positioned(left: 12, bottom: 12, child: widget.onBadge!),
          if (n > 1 && widget.counter)
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
                child: Text('${_i + 1}/$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          if (n > 1 && !widget.counter && !widget.thumbs)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var k = 0; k < n; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: k == _i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(color: k == _i ? Hp.accent : Colors.black26, borderRadius: BorderRadius.circular(3)),
                  ),
              ]),
            ),
        ]),
      ),
      if (n > 1 && widget.thumbs)
        Container(
          color: ground,
          height: 62,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: n,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, k) => GestureDetector(
              onTap: () => _c.animateToPage(k, duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
              child: Container(
                width: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: k == _i ? Hp.accent : Colors.black12, width: k == _i ? 2 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(padding: const EdgeInsets.all(3), child: CachedNetworkImage(imageUrl: widget.photos[k], fit: BoxFit.contain, errorWidget: (_, __, ___) => const SizedBox())),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// A small coloured tag ("Vegetarian", "Organic").
class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key, this.tone = 'plain', this.icon});
  final String label;
  final String tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = switch (tone) {
      'ok' => Hp.veg,
      'bad' => Hp.nonVeg,
      'warn' => const Color(0xFFB45309),
      _ => Hp.muted(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

/// The tags for the product (its own badges, "Only 3 left", warranty).
List<Widget> productTags(MenuItem item) {
  final p = item.product;
  if (p == null) return const [];
  return [
    for (final b in p.badges) TagChip(b.label, tone: b.tone, icon: b.key == 'rx' ? Icons.medication_outlined : null),
    if (item.available && p.lowStock != null) TagChip('Only ${p.lowStock} left', tone: 'warn', icon: Icons.local_fire_department_outlined),
  ];
}

/// "4.3 ★" in a green pill (clothes, grocery) with an optional count.
class RatingPill extends StatelessWidget {
  const RatingPill({super.key, required this.rating, this.count = 0, this.onImage = false});
  final double rating;
  final int count;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    final good = rating >= 4;
    final bg = good ? const Color(0xFF16A34A) : (rating >= 3 ? const Color(0xFFF59E0B) : const Color(0xFFDC2626));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: onImage ? Colors.white.withValues(alpha: 0.95) : bg, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: onImage ? Colors.black87 : Colors.white)),
        const SizedBox(width: 3),
        Icon(Icons.star_rounded, size: 13, color: onImage ? bg : Colors.white),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(width: 1, height: 11, color: onImage ? Colors.black26 : Colors.white54),
          const SizedBox(width: 6),
          Text(_compact(count), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: onImage ? Colors.black54 : Colors.white)),
        ],
      ]),
    );
  }
}

String _compact(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k' : '$n';

/// Five stars with the rating beside them (Amazon).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.count = 0});
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(width: 4),
      for (var k = 1; k <= 5; k++)
        Icon(rating >= k ? Icons.star_rounded : (rating >= k - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded), size: 16, color: const Color(0xFFF59E0B)),
      if (count > 0) ...[const SizedBox(width: 6), Text('(${_compact(count)})', style: TextStyle(fontSize: 12.5, color: Hp.accent, fontWeight: FontWeight.w600))],
    ]);
  }
}

/// How a choice group is drawn.
enum ChoiceStyle {
  /// Round or pill boxes with the name only: sizes and colours (Myntra).
  chips,

  /// Boxes with the name and its own price: pack sizes and variants (Amazon, grocery).
  cards,

  /// Radio / checkbox rows with the price at the end (food).
  rows,
}

/// One choice group (a size, a colour, an add-on) in the style the layout asks for.
class ChoiceBlock extends StatelessWidget {
  const ChoiceBlock({super.key, required this.ctl, required this.group, this.style = ChoiceStyle.rows, this.heading});
  final ProductCtl ctl;
  final ChoiceGroup group;
  final ChoiceStyle style;
  final String? heading;

  /// What to print beside an option. A choice on an item priced through its options says the price; on an item with its own
  /// price it says only what it adds. An add-on says what it adds, or Free.
  String? _price(Option o) {
    if (!group.isVariation) return o.price > 0 ? '+${rs(o.price)}' : 'Free';
    if (ctl.item.price <= 0) return group.options.map((x) => x.price).toSet().length > 1 ? rs(o.price) : null;
    return o.price > 0 ? '+${rs(o.price)}' : null;
  }

  @override
  Widget build(BuildContext context) {
    final req = ctl.required(group);
    final muted = Hp.muted(context);
    final faint = Hp.faint(context);
    final title = Row(children: [
      Text((heading ?? group.name).toUpperCase(), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: Hp.text(context))),
      const SizedBox(width: 8),
      Text(req ? 'Required' : (group.max > 1 ? 'Up to ${group.max}' : 'Optional'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: req ? Hp.bad : faint)),
    ]);

    Widget body;
    switch (style) {
      case ChoiceStyle.chips:
        body = Wrap(spacing: 10, runSpacing: 10, children: [
          for (final o in group.options)
            _Selectable(
              on: ctl.isPicked(group, o),
              onTap: () => ctl.toggle(group, o),
              radius: 28,
              minWidth: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(o.name, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: ctl.isPicked(group, o) ? Hp.accent : Hp.text(context))),
            ),
        ]);
      case ChoiceStyle.cards:
        body = Wrap(spacing: 10, runSpacing: 10, children: [
          for (final o in group.options)
            _Selectable(
              on: ctl.isPicked(group, o),
              onTap: () => ctl.toggle(group, o),
              radius: 12,
              minWidth: 92,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.name, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Hp.text(context))),
                const SizedBox(height: 2),
                if (_price(o) != null) Text(_price(o)!, style: TextStyle(fontSize: 12.5, color: muted, fontWeight: FontWeight.w600)),
              ]),
            ),
        ]);
      case ChoiceStyle.rows:
        body = Column(children: [
          for (final o in group.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Selectable(
                on: ctl.isPicked(group, o),
                onTap: () => ctl.toggle(group, o),
                radius: 14,
                minWidth: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                child: Row(children: [
                  _Mark(single: group.max <= 1, on: ctl.isPicked(group, o)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(o.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 10),
                  if (_price(o) != null) Text(_price(o)!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: muted)),
                ]),
              ),
            ),
        ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 10), body]),
    );
  }
}

class _Selectable extends StatelessWidget {
  const _Selectable({required this.on, required this.onTap, required this.child, required this.radius, required this.minWidth, required this.padding});
  final bool on;
  final VoidCallback onTap;
  final Widget child;
  final double radius;
  final double minWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        constraints: BoxConstraints(minWidth: minWidth),
        padding: padding,
        decoration: BoxDecoration(
          color: on ? Hp.tint(context) : null,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: on ? Hp.accent : Hp.lineStrong(context), width: on ? 1.6 : 1),
        ),
        child: child,
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.single, required this.on});
  final bool single;
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: single ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: single ? null : BorderRadius.circular(5),
          color: on && !single ? Hp.accent : null,
          border: Border.all(color: on ? Hp.accent : Hp.lineStrong(context), width: single && on ? 5 : 1.5),
        ),
        child: on && !single ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
      );
}

/// A heading with a rule above it, as every block on a product page starts.
class BlockTitle extends StatelessWidget {
  const BlockTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// A white band on the grey page: the "card" each block of a product page sits in.
class Band extends StatelessWidget {
  const Band({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.top = 8});
  final Widget child;
  final EdgeInsets padding;
  final double top;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: EdgeInsets.only(top: top),
        padding: padding,
        color: Hp.surface(context),
        child: child,
      );
}

/// Label / value rows, striped (Amazon's specification table).
class SpecTable extends StatelessWidget {
  const SpecTable({super.key, required this.rows, this.striped = true});
  final List<({String label, String value})> rows;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Hp.line(context)), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var k = 0; k < rows.length; k++)
          Container(
            color: striped && k.isEven ? Hp.surface2(context) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 118, child: Text(rows[k].label, style: TextStyle(fontSize: 13, color: Hp.muted(context), fontWeight: FontWeight.w600))),
              Expanded(child: Text(rows[k].value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35))),
            ]),
          ),
      ]),
    );
  }
}

/// Everything the shop wrote about the product apart from its price and choices: facts, then each section the category asks
/// for (ingredients, care, specifications...). Shows only what is filled in; an empty product shows nothing.
class DetailSections extends StatelessWidget {
  const DetailSections({super.key, required this.item, this.accordion = true, this.skip = const {}, this.includeFacts = true});
  final MenuItem item;
  final bool accordion;

  /// Section keys a layout draws itself (the size chart, the in-the-box list).
  final Set<String> skip;
  final bool includeFacts;

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    if (p == null) return const SizedBox.shrink();
    final facts = <({String label, String value})>[
      if (p.brand != null) (label: 'Brand', value: p.brand!),
      ...p.rows,
      if (p.soldByWeight) (label: 'Sold by', value: p.unit == null ? 'Weight' : 'Weight (${p.unit})') else if (p.unit != null && p.unit != 'piece') (label: 'Unit', value: p.unit!),
      if (p.warrantyMonths != null) (label: 'Warranty', value: _months(p.warrantyMonths!)),
    ];
    final tiles = <Widget>[];
    if (includeFacts && facts.isNotEmpty) tiles.add(_tile(context, 'Specifications', SpecTable(rows: facts)));
    for (final s in p.sections) {
      if (skip.contains(s.key)) continue;
      Widget body;
      if (s.specs.isNotEmpty) {
        body = SpecTable(rows: s.specs);
      } else if (s.list.isNotEmpty) {
        body = Wrap(spacing: 6, runSpacing: 6, children: [for (final x in s.list) TagChip(x, tone: 'warn')]);
      } else if ((s.text ?? '').isNotEmpty) {
        body = Text(s.text!, style: TextStyle(fontSize: 13.5, height: 1.5, color: Hp.text(context)));
      } else {
        continue;
      }
      tiles.add(_tile(context, s.title, body));
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: tiles);
  }

  Widget _tile(BuildContext context, String title, Widget body) {
    if (!accordion) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [BlockTitle(title), body]),
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        iconColor: Hp.muted(context),
        collapsedIconColor: Hp.muted(context),
        children: [Align(alignment: Alignment.centerLeft, child: body)],
      ),
    );
  }
}

String _months(int m) => m % 12 == 0 ? '${m ~/ 12} year${m == 12 ? '' : 's'}' : '$m months';

/// A line of icon and text ("Ready in about 20 min", "1 year warranty").
class InfoLine extends StatelessWidget {
  const InfoLine(this.icon, this.text, {super.key, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color ?? Hp.muted(context)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: color ?? Hp.text(context), fontWeight: FontWeight.w600))),
        ]),
      );
}

/// What the customer needs to know about getting it: how long, what it costs, when it is free.
List<Widget> deliveryLines(Shop shop, MenuItem item) {
  final p = item.product;
  final lines = <Widget>[];
  final mins = p?.prepMinutes ?? shop.prepMinutes;
  if (mins > 0) lines.add(InfoLine(Icons.schedule_rounded, 'Ready in about $mins min'));
  if (shop.supportsDelivery) {
    if (shop.freeDeliveryOver != null && shop.freeDeliveryOver! > 0) {
      lines.add(InfoLine(Icons.local_shipping_outlined, 'Free delivery on orders over ${rs(shop.freeDeliveryOver!)}'));
    } else if (shop.baseDeliveryFee > 0) {
      lines.add(InfoLine(Icons.local_shipping_outlined, 'Delivery from ${rs(shop.baseDeliveryFee)}'));
    } else {
      lines.add(const InfoLine(Icons.local_shipping_outlined, 'Free delivery', color: Color(0xFF15803D)));
    }
  }
  if (shop.supportsPickup) lines.add(const InfoLine(Icons.storefront_outlined, 'Pick up from the shop'));
  return lines;
}

/// The offers the shop is running, one under another (Myntra's "Best offers", Amazon's "Offers").
class OffersBand extends StatelessWidget {
  const OffersBand({super.key, required this.offers});
  final List<ShopOffer> offers;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const BlockTitle('Offers for you'),
      for (final o in offers.take(3))
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF16A34A).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.25))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.local_offer_rounded, size: 17, color: Color(0xFF15803D)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                if ((o.subtitle ?? '').isNotEmpty) Text(o.subtitle!, style: TextStyle(fontSize: 12.5, color: Hp.muted(context), height: 1.35)),
                if ((o.code ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(border: Border.all(color: Hp.lineStrong(context), style: BorderStyle.solid), borderRadius: BorderRadius.circular(6)),
                      child: Text('Use ${o.code}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// More from the same shop, as a row of small cards.
class RelatedRow extends StatelessWidget {
  const RelatedRow({super.key, required this.items, required this.shop, required this.onOpen, this.title = 'More from this shop', this.card = 148, this.tall = false});
  final List<MenuItem> items;
  final Shop shop;
  final void Function(MenuItem) onOpen;
  final String title;
  final double card;

  /// A taller photo for clothes.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final photoH = tall ? card * 1.25 : card;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: BlockTitle(title)),
      SizedBox(
        height: photoH + 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, k) {
            final it = items[k];
            final photo = productPhotos(it, shop.categoryKey).first;
            final mrp = it.product?.mrp;
            return GestureDetector(
              onTap: () => onOpen(it),
              child: SizedBox(
                width: card,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(width: card, height: photoH, child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover, errorWidget: (_, __, ___) => ColoredBox(color: Hp.surface2(context)))),
                  ),
                  const SizedBox(height: 8),
                  Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.25)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(rs(it.hasChoices ? it.fromPrice : it.price), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                    if (mrp != null && mrp > it.price && it.price > 0) ...[
                      const SizedBox(width: 6),
                      Text(rs(mrp), style: TextStyle(fontSize: 11.5, color: Hp.faint(context), decoration: TextDecoration.lineThrough)),
                    ],
                  ]),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

/// The sticky bar at the bottom of every product page. [children] fill it; it keeps clear of the phone's gesture bar.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.children, this.error});
  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Hp.surface(context),
      elevation: 12,
      shadowColor: Colors.black38,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(fontSize: 12.5, color: Hp.bad, fontWeight: FontWeight.w600))),
            Row(children: children),
          ]),
        ),
      ),
    );
  }
}

/// The [-] 1 [+] control.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.ctl, this.compact = false});
  final ProductCtl ctl;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, VoidCallback f) => InkWell(
          customBorder: const CircleBorder(),
          onTap: f,
          child: SizedBox(width: compact ? 36 : 40, height: 46, child: Icon(i, size: 19, color: Hp.accent)),
        );
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Hp.lineStrong(context))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, () => ctl.setQty(ctl.qty - 1)),
        SizedBox(width: 26, child: Text('${ctl.qty}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        btn(Icons.add_rounded, () => ctl.setQty(ctl.qty + 1)),
      ]),
    );
  }
}

/// The product's description, split into bullet points when it is written line by line (Amazon's "About this item").
class DescriptionText extends StatelessWidget {
  const DescriptionText({super.key, required this.text, this.bullets = false, this.maxLines});
  final String text;
  final bool bullets;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 14, height: 1.5, color: Hp.text(context));
    final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (bullets && lines.length > 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 8, right: 10), child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: Hp.muted(context)))),
              Expanded(child: Text(l.replaceFirst(RegExp(r'^[-•*]\s*'), ''), style: style)),
            ]),
          ),
      ]);
    }
    return Text(text, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis, style: style);
  }
}
