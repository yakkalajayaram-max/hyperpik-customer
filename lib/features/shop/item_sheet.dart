import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/media.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

/// What the customer chose on the product page: the options and how many.
typedef ItemChoice = ({List<Option> chosen, int quantity});

/// The website's item sheet: the photo, the name and what it is, every question the dish needs answered (a choice says which
/// dish it is and is compulsory; an add-on is an extra and is not), a quantity, and "Add · ₹". Pops an [ItemChoice], or
/// nothing when closed.
///
/// Nothing is pre-selected: defaulting a required choice would charge for a portion the customer never picked.
class ItemSheet extends StatefulWidget {
  const ItemSheet({super.key, required this.item, required this.categoryKey, required this.canOrder, this.blockedReason});
  final MenuItem item;

  /// The shop's category key, for the same stock photo the website uses when the dish has none.
  final String categoryKey;
  final bool canOrder;
  final String? blockedReason;

  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  final Map<String, Set<String>> _picked = {};
  int _qty = 1;
  String? _error;

  List<ChoiceGroup> get _groups => widget.item.groups;

  /// Only a variation counts as compulsory: it says WHICH dish this is. A minimum on an add-on is a mistake by the shop.
  bool _required(ChoiceGroup g) => g.isVariation && g.min > 0;

  List<ChoiceGroup> get _unanswered => _groups.where((g) => _required(g) && (_picked[g.id]?.length ?? 0) < g.min).toList();

  List<Option> get _chosen => [
        for (final g in _groups) for (final o in g.options) if (_picked[g.id]?.contains(o.id) ?? false) o,
      ];

  num get _unit => _chosen.fold<num>(widget.item.price, (a, o) => a + o.price);

  void _toggle(ChoiceGroup g, Option o) {
    final set = _picked.putIfAbsent(g.id, () => {});
    setState(() {
      _error = null;
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
    });
  }

  void _add() {
    final un = _unanswered;
    if (un.isNotEmpty) {
      setState(() => _error = 'Please choose ${un.map((g) => g.name).join(' and ')}.');
      return;
    }
    Navigator.pop<ItemChoice>(context, (chosen: _chosen, quantity: _qty));
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Hp.lineStrong(context), width: 0.8)), child: Icon(icon, size: 14)),
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final photo = Media.item(widget.categoryKey, item.id, item.imageUrl);
    final muted = Hp.muted(context);
    final faint = Hp.faint(context);
    final un = _unanswered;
    final outOfStock = !item.available || !widget.canOrder;
    final label = !widget.canOrder
        ? (widget.blockedReason ?? 'Not available right now')
        : !item.available
            ? (item.unavailableLabel ?? 'Out of stock')
            : un.isNotEmpty
                ? 'Add'
                : 'Add · ₹${(_unit * _qty).toStringAsFixed(0)}';

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88, maxWidth: 448),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 192,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: Hp.surface2(context)),
              CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Center(child: Text('🍽️', style: TextStyle(fontSize: 56)))),
              Positioned(
                top: 12,
                right: 12,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Hp.surface(context).withValues(alpha: 0.9), shape: BoxShape.circle), child: Icon(Icons.close_rounded, size: 16, color: muted)),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: const TextStyle(fontSize: 24, height: 1.33, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
              const SizedBox(height: 4),
              if ((item.description ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 20), child: Text(item.description!, style: TextStyle(fontSize: 14, height: 1.43, color: muted))) else const SizedBox(height: 16),
              for (final g in _groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text.rich(TextSpan(style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: muted), children: [
                        TextSpan(text: g.name.toUpperCase()),
                        if (_required(g)) const TextSpan(text: ' · REQUIRED', style: TextStyle(color: Hp.bad)) else TextSpan(text: ' · OPTIONAL', style: TextStyle(color: faint)),
                        if (g.max > 1) TextSpan(text: ' · UP TO ${g.max}', style: TextStyle(color: faint)),
                      ])),
                    ),
                    for (final o in g.options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _toggle(g, o),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: (_picked[g.id]?.contains(o.id) ?? false) ? Hp.tint(context) : null,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: (_picked[g.id]?.contains(o.id) ?? false) ? Hp.accent : Hp.line(context), width: 0.8),
                            ),
                            child: Row(children: [
                              _mark(g.max <= 1, _picked[g.id]?.contains(o.id) ?? false),
                              const SizedBox(width: 8),
                              Expanded(child: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.43))),
                              const SizedBox(width: 12),
                              Text(g.isVariation ? '₹${o.price.toStringAsFixed(0)}' : (o.price > 0 ? '+₹${o.price.toStringAsFixed(0)}' : 'Free'), style: TextStyle(fontSize: 14, height: 1.43, color: faint)),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Quantity', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500)),
                  Row(children: [
                    _stepBtn(Icons.remove_rounded, () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1)),
                    SizedBox(width: 44, child: Text('$_qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
                    _stepBtn(Icons.add_rounded, () => setState(() => _qty += 1)),
                  ]),
                ]),
              ),
              if (un.isNotEmpty && _error == null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Still to choose: ${un.map((g) => g.name).join(', ')}', style: TextStyle(fontSize: 13, height: 1.33, color: muted))),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.bad))),
              SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: outOfStock || un.isNotEmpty ? null : _add, child: Text(label))),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ]),
          ),
        ]),
      ),
    );
  }

  /// The little radio / checkbox at the start of an option.
  Widget _mark(bool single, bool on) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: single ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: single ? null : BorderRadius.circular(4),
          color: on && !single ? Hp.accent : null,
          border: Border.all(color: on ? Hp.accent : Hp.lineStrong(context), width: single && on ? 4.5 : 1.5),
        ),
        child: on && !single ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
      );
}
