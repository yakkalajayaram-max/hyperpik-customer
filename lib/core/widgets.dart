import 'package:flutter/material.dart';

import 'favourites.dart';
import 'theme.dart';

/// A grey block that breathes while something loads, so the screen holds its shape instead of showing a spinner.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 12});
  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Hp.isDark(context) ? const Color(0xFF231C3A) : const Color(0xFFE9E4F5);
    final hi = Hp.isDark(context) ? const Color(0xFF2D2548) : const Color(0xFFF3EFFB);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(color: Color.lerp(base, hi, _c.value), borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// A small coloured fact: rating, time, distance.
class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.text, this.icon, this.color, this.filled = false});
  final String text;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Hp.muted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: filled ? Colors.white : c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: filled ? Colors.white : c)),
      ]),
    );
  }
}

/// The ADD button that turns into a − 1 + stepper once the dish is in the cart.
class AddStepper extends StatelessWidget {
  const AddStepper({super.key, required this.quantity, required this.onAdd, this.onRemove, this.enabled = true, this.customisable = false, this.muted = false});
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback? onRemove;
  final bool enabled;

  /// The shop is closed or out of range: the button still answers (with the reason) but reads as unavailable.
  final bool muted;

  /// A dish with choices: the button always opens the choices, and the count is shown beside it.
  final bool customisable;

  @override
  Widget build(BuildContext context) {
    if (quantity == 0 || customisable) {
      return SizedBox(
        height: 38,
        width: 92,
        child: OutlinedButton(
          onPressed: enabled ? onAdd : null,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            side: BorderSide(color: muted || !enabled ? Hp.line(context) : Hp.accent.withValues(alpha: 0.5)),
            foregroundColor: muted ? Hp.muted(context) : Hp.accent,
          ),
          child: Text(quantity > 0 ? 'ADD · $quantity' : 'ADD', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.3)),
        ),
      );
    }
    return Container(
      height: 38,
      width: 112,
      decoration: BoxDecoration(color: Hp.accent, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: onRemove, icon: const Icon(Icons.remove, size: 18, color: Colors.white), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 34, minHeight: 36)),
          Text('$quantity', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
          IconButton(onPressed: onAdd, icon: const Icon(Icons.add, size: 18, color: Colors.white), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 34, minHeight: 36)),
        ],
      ),
    );
  }
}

/// The veg / non-veg mark. Drawn only when the shop has said which it is; never guessed.
class DietMark extends StatelessWidget {
  const DietMark({super.key, required this.veg});
  final bool veg;

  @override
  Widget build(BuildContext context) {
    final c = veg ? Hp.veg : Hp.nonVeg;
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(border: Border.all(color: c, width: 1.6), borderRadius: BorderRadius.circular(4)),
      child: Center(child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: c))),
    );
  }
}

/// A shop's logo in a rounded tile, or its initial on a tinted tile when there is no logo.
class ShopAvatar extends StatelessWidget {
  const ShopAvatar({super.key, required this.name, this.logoUrl, this.size = 64});
  final String name;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Hp.tint(context),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Hp.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl == null
          ? Center(child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w900, color: Hp.accent)))
          : Padding(padding: EdgeInsets.all(size * 0.08), child: Image.network(logoUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(Icons.storefront, color: Hp.accent, size: size * 0.45))),
    );
  }
}

/// A shop's heart. Filled when it is a favourite; tapping signs in first if the customer is a guest.
class HeartButton extends StatelessWidget {
  const HeartButton({super.key, required this.shopId, this.onDark = false, this.size = 24});
  final String shopId;
  final bool onDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Favourites.instance,
      builder: (context, _) {
        final on = Favourites.instance.contains(shopId);
        return IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: on ? 'Remove from favourites' : 'Add to favourites',
          onPressed: () async {
            final ok = await Favourites.instance.toggle(shopId);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in from the Account tab to save favourites.')));
            }
          },
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(on),
              size: size,
              color: on ? const Color(0xFFE11D48) : (onDark ? Colors.white : Hp.muted(context)),
            ),
          ),
        );
      },
    );
  }
}
