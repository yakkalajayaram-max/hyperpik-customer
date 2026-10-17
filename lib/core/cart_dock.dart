import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/cart/cart_screen.dart';
import 'cart.dart';
import 'nav.dart';
import 'theme.dart';

/// The app's one navigator, so the dock (which sits above every screen) can open a cart.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// How tall the floating dock is right now (0 when hidden). Scroll views read it to leave room at their end, so the last
/// shop or dish is never hidden behind it.
final ValueNotifier<double> dockExtent = ValueNotifier<double>(0);

/// Opens the cart screen (all carts) from anywhere: the header icon, a reorder, a notification.
void openCart() {
  appNavigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => const CartScreen()));
}

/// Screens that should not show the dock (checkout, address picker, sign in) hold it while they are open.
class DockGate {
  static final ValueNotifier<int> holds = ValueNotifier<int>(0);
  static void hold() => _later(() => holds.value++);
  static void release() => _later(() => holds.value = holds.value > 0 ? holds.value - 1 : 0);

  /// Changes made while the framework is building or tearing down widgets are applied right after the frame.
  static void _later(VoidCallback f) => WidgetsBinding.instance.addPostFrameCallback((_) => f());
}

/// Mix into a screen's State to keep the cart dock hidden while it is open.
mixin HidesCartDock<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    DockGate.hold();
  }

  @override
  void dispose() {
    DockGate.release();
    super.dispose();
  }
}

/// Tells the dock how many full screens are on the stack: one means the tab shell is showing, which has a bottom bar the
/// dock must sit above.
class DockRouteObserver extends NavigatorObserver {
  static final ValueNotifier<int> depth = ValueNotifier<int>(1);

  // The first route (the app shell) is pushed through this observer too, so counting starts at zero.
  int _pages = 0;

  void _apply() => WidgetsBinding.instance.addPostFrameCallback((_) => depth.value = _pages);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages += 1;
      _apply();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages = (_pages - 1).clamp(0, 1000);
      _apply();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      _pages = (_pages - 1).clamp(0, 1000);
      _apply();
    }
  }
}

/// The floating cart bar, Zomato style: a card per cart that you swipe between. It sits above every screen and appears
/// as soon as anything is in a cart, so a customer can keep several going and jump back to any of them.
class CartDock extends StatefulWidget {
  const CartDock({super.key});

  @override
  State<CartDock> createState() => _CartDockState();
}

class _CartDockState extends State<CartDock> {
  static const _cardHeight = 48.0;
  static const _dotsHeight = 16.0;

  final _controller = PageController();
  String? _leadId;
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open(BuildContext context, ShopCart cart) {
    HapticFeedback.selectionClick();
    appNavigatorKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => CartScreen(shopId: cart.shopId)));
  }

  void _publish(double v) {
    if (dockExtent.value == v) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => dockExtent.value = v);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Cart.instance, DockGate.holds, DockRouteObserver.depth, shellTab]),
      builder: (context, _) {
        final carts = Cart.instance.carts;
        final onShell = DockRouteObserver.depth.value <= 1;
        // The Cart tab already lists every cart, so the dock would only repeat it.
        final visible = carts.isNotEmpty && DockGate.holds.value == 0;
        if (!visible) {
          _publish(0);
          return const SizedBox.shrink();
        }

        final safe = MediaQuery.of(context).padding.bottom;
        // 24 clears the raised cart button, which stands 18 above the bar.
        final bottom = safe + kNavExtent + 16;
        final extent = _cardHeight + (carts.length > 1 ? _dotsHeight : 0) + 16;
        _publish(extent + (onShell ? 0 : 0));

        // A cart that just changed moves to the front: bring the carousel back to it.
        if (_leadId != carts.first.shopId) {
          _leadId = carts.first.shopId;
          if (_controller.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_controller.hasClients) _controller.animateToPage(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
            });
          }
        }

        return Positioned(
          left: 0,
          right: 0,
          bottom: bottom,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Opacity(opacity: t.clamp(0, 1), child: Transform.translate(offset: Offset(0, (1 - t) * 40), child: child)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: _cardHeight,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: carts.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 448), child: _DockCard(cart: carts[i], named: carts.length > 1, onTap: () => _open(context, carts[i])))),
                  ),
                ),
              ),
              if (carts.length > 1)
                SizedBox(
                  height: _dotsHeight,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < carts.length && i < 8; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                        width: i == _page ? 16 : 6,
                        height: 5,
                        decoration: BoxDecoration(color: i == _page ? Hp.accent : Hp.muted(context).withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
                      ),
                  ]),
                ),
            ]),
          ),
        );
      },
    );
  }
}

class _DockCard extends StatelessWidget {
  const _DockCard({required this.cart, required this.onTap, this.named = false});
  final ShopCart cart;
  final VoidCallback onTap;

  /// More than one cart is going: say which shop this bar is for.
  final bool named;

  @override
  Widget build(BuildContext context) {
    final items = cart.count;
    final total = '₹${cart.subtotal.toStringAsFixed(0)}';
    const style = TextStyle(color: Colors.white, fontSize: 14, height: 1.43, fontWeight: FontWeight.w600);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Hp.accent,
            boxShadow: const [BoxShadow(color: Hp.glow, blurRadius: 24, offset: Offset(0, 8))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text('${named ? '${cart.shopName} · ' : ''}$items item${items == 1 ? '' : 's'} · $total', maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
            const SizedBox(width: 12),
            const Row(mainAxisSize: MainAxisSize.min, children: [Text('View Cart', style: style), SizedBox(width: 4), Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16)]),
          ]),
        ),
      ),
    );
  }
}

/// Space at the end of a scrolling list equal to the dock's height, so the last item can be scrolled clear of it.
class DockSpacer extends StatelessWidget {
  const DockSpacer({super.key, this.base = 24});
  final double base;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<double>(valueListenable: dockExtent, builder: (_, e, __) => SizedBox(height: base + e));
}
