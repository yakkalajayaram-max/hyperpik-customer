import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cart_dock.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';

/// The website's mobile bar: Home, Orders, a round Cart button that stands 4 px above the bar, Addresses, Account. The
/// selected tab is in the accent colour; the cart button opens the cart (every shop's bag), it is not a page of the shell.
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.selected, required this.onSelect});

  /// The tab that is showing, or null on a page pushed over the tabs (nothing is highlighted there).
  final int? selected;
  final ValueChanged<int> onSelect;

  static const _left = [
    (tabHome, Icons.home_outlined, 'Home'),
    (tabOrders, Icons.receipt_long_outlined, 'Orders'),
  ];
  static const _right = [
    (tabAddresses, Icons.location_on_outlined, 'Addresses'),
    (tabAccount, Icons.person_outline_rounded, 'Account'),
  ];

  Widget _tab(BuildContext context, (int, IconData, String) it) {
    final on = selected == it.$1;
    final color = on ? Hp.accent : Hp.faint(context);
    return Semantics(
      button: true,
      selected: on,
      label: it.$3,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(it.$1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(it.$2, size: 20, color: color),
            const SizedBox(height: 2),
            Text(it.$3, style: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: kNavExtent + bottom,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: Container(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 6.4 + bottom),
            decoration: BoxDecoration(
              color: Hp.surface(context).withValues(alpha: 0.96),
              border: Border(top: BorderSide(color: Hp.line(context).withValues(alpha: 0.8))),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (final it in _left) _tab(context, it),
              const SizedBox(width: 56),
              for (final it in _right) _tab(context, it),
            ]),
          ),
        ),
        Positioned(
          top: -4,
          left: 0,
          right: 0,
          child: Center(
            child: Semantics(
              button: true,
              label: 'Cart',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  openCart();
                },
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: Hp.accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Hp.glow, blurRadius: 24, offset: Offset(0, 8))]),
                  child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
