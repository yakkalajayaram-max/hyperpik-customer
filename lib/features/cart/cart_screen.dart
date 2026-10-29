import 'dart:async';

import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/api.dart';
import '../../core/cart.dart';
import '../../core/cart_dock.dart';
import '../../core/media.dart';
import '../../core/models.dart';
import '../../core/nav.dart';
import '../../core/orders_models.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import '../account/addresses_screen.dart';
import '../account/sign_in_screen.dart';
import '../orders/order_detail_screen.dart';

/// The website's "Cart & checkout": the bag, the offers, how you want it, where to, how you pay, and one button, on one
/// page. [shopId] picks which shop's bag to show first; a customer with several carts switches with the chips on top.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key, this.shopId});
  final String? shopId;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with HidesCartDock {
  final _code = TextEditingController();
  final _note = TextEditingController();
  late final TextEditingController _email = TextEditingController(text: Api.user?.email ?? '');
  final Razorpay _razorpay = Razorpay();

  String? _shopId;
  Shop? _shop;
  List<MenuItem> _menu = const [];
  List<Address>? _addresses;
  String? _addressId;

  /// Who the rider rings for THIS order, when the customer changed it. Reset with the address: it belongs to the
  /// delivery it was typed for.
  String? _contactOverride;
  bool _pickup = false;

  /// The time chosen under "Schedule for later", or null for as soon as possible.
  DateTime? _slot;
  String _method = 'razorpay';
  Quote? _quote;
  List<OfferInfo> _offers = const [];
  bool _offersExpanded = false;
  String? _applied; // the coupon reference in play: a code the customer typed or an offer's id
  String? _appliedTitle;
  String? _couponError;
  String? _error;
  bool _pricing = false;
  bool _placing = false;
  PlacedOrder? _pending;
  Timer? _debounce;
  String _signature = '';

  ShopCart? get _cart => _shopId == null ? null : Cart.instance.cartFor(_shopId!);

  @override
  void initState() {
    super.initState();
    _shopId = widget.shopId ?? Cart.instance.carts.firstOrNull?.shopId;
    _applied = _cart?.coupon;
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaid);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPayError);
    Cart.instance.addListener(_cartChanged);
    _loadShop();
    _loadAddresses();
  }

  @override
  void dispose() {
    Cart.instance.removeListener(_cartChanged);
    _razorpay.clear();
    _debounce?.cancel();
    _code.dispose();
    _note.dispose();
    _email.dispose();
    super.dispose();
  }

  // ---- loading ---------------------------------------------------------------------------------------------------

  Future<void> _loadShop() async {
    final cart = _cart;
    if (cart == null) return;
    try {
      final m = await Api.shop(cart.shopHandle);
      if (mounted && _shopId == cart.shopId) {
        setState(() {
          _shop = m.shop;
          _menu = m.items;
        });
      }
    } catch (_) {
      // The page still works without the shop's open/closed state; checkout says so if it is closed.
    }
  }

  Future<void> _loadAddresses() async {
    if (Api.user == null) return;
    try {
      final list = await Api.addresses();
      if (!mounted) return;
      setState(() {
        _addresses = list;
        if (_addressId == null || !list.any((a) => a.id == _addressId)) {
          _addressId = list.isEmpty ? null : (list.firstWhere((a) => a.isDefault, orElse: () => list.first)).id;
        }
      });
      _price();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Address? get _address => _addresses?.where((a) => a.id == _addressId).firstOrNull;

  String get _sig => '$_shopId|${_cart?.lines.map((l) => '${l.key}x${l.quantity}').join(',')}';

  void _cartChanged() {
    final cart = _cart;
    if (cart == null) {
      // Emptied (ordered, or the last line removed): another bag, or back out.
      final next = Cart.instance.carts.firstOrNull;
      if (next == null) {
        setState(() {});
        return;
      }
      _switchTo(next.shopId);
      return;
    }
    if (_sig != _signature) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), _price);
    }
    setState(() {});
  }

  void _switchTo(String id) {
    setState(() {
      _shopId = id;
      _shop = null;
      _quote = null;
      _offers = const [];
      _applied = _cart?.coupon;
      _appliedTitle = null;
      _couponError = null;
      _error = null;
      _code.clear();
    });
    _loadShop();
    _price();
  }

  List<Map<String, dynamic>> get _lines => [
        for (final l in _cart?.lines ?? const <CartLine>[]) {'itemId': l.itemId, 'quantity': l.quantity, 'optionIds': l.optionIds},
      ];

  Future<void> _price() async {
    _signature = _sig;
    final cart = _cart;
    if (cart == null || Api.user == null) return;
    if (!_pickup && _address == null) {
      setState(() => _quote = null);
      return;
    }
    setState(() {
      _pricing = true;
      _error = null;
    });
    try {
      await Api.syncCart(cart.shopId, _lines);
      Quote q;
      try {
        q = await Api.quote(shopId: cart.shopId, addressId: _pickup ? null : _addressId, pickup: _pickup, method: _method, coupon: _applied);
      } on ApiException catch (e) {
        // An offer that does not apply must not hide the bill: say why and price it without.
        if (_applied == null) rethrow;
        if (mounted) {
          setState(() {
            _couponError = e.message;
            _applied = null;
            _appliedTitle = null;
          });
          Cart.instance.setCoupon(cart.shopId, null);
        }
        q = await Api.quote(shopId: cart.shopId, addressId: _pickup ? null : _addressId, pickup: _pickup, method: _method);
      }
      if (mounted) {
        setState(() {
          _quote = q;
          // A chosen time the shop no longer offers (the clock moved on, or pickup/delivery was switched) is dropped.
          if (_slot != null && !q.slots.any((s) => s.isAtSameMomentAs(_slot!))) _slot = null;
        });
      }
      // The admin switched the chosen method off (e.g. cash on delivery): move to one that is on and price again.
      if (q.paymentMethods.isNotEmpty && !q.paymentMethods.contains(_method)) {
        if (mounted) setState(() => _method = q.paymentMethods.first);
        _price();
        return;
      }
      _loadOffers(q);
    } on ApiException catch (e) {
      if (_wantsPhone(e.message) && await _askPhone()) {
        if (mounted) _price();
        return;
      }
      if (mounted) {
        setState(() {
          _quote = null;
          _error = e.message;
        });
      }
    } finally {
      if (mounted) setState(() => _pricing = false);
    }
  }

  Future<void> _loadOffers(Quote q) async {
    final cart = _cart;
    if (cart == null) return;
    try {
      final o = await Api.offers(shopId: cart.shopId, subtotal: q.subtotal, delivery: q.deliveryFee, method: _method);
      if (mounted && _shopId == cart.shopId) setState(() => _offers = o);
    } catch (_) {}
  }

  static bool _wantsPhone(String m) => m.toLowerCase().contains('contact number');

  /// A delivery needs a number the shop and rider can ring. Asked for here, once, when the account has none.
  Future<bool> _askPhone() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your mobile number'),
        content: TextField(controller: c, keyboardType: TextInputType.phone, decoration: const InputDecoration(prefixText: '+91  ', hintText: '10-digit number')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await Api.saveProfile(phone: c.text.trim());
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    }
  }

  // ---- offers ----------------------------------------------------------------------------------------------------

  void _applyOffer(OfferInfo o) {
    final ref = o.couponId ?? o.code;
    if (ref == null) return;
    _code.clear();
    setState(() {
      _applied = ref;
      _appliedTitle = o.title;
      _couponError = null;
    });
    Cart.instance.setCoupon(_shopId!, ref);
    _price();
  }

  void _applyCode() {
    final c = _code.text.trim().toUpperCase();
    if (c.isEmpty) return;
    setState(() {
      _applied = c;
      _appliedTitle = null;
      _couponError = null;
    });
    Cart.instance.setCoupon(_shopId!, c);
    _price();
  }

  void _clearOffer() {
    _code.clear();
    setState(() {
      _applied = null;
      _appliedTitle = null;
      _couponError = null;
    });
    Cart.instance.setCoupon(_shopId!, null);
    _price();
  }

  // ---- placing the order -----------------------------------------------------------------------------------------

  Future<void> _place() async {
    final cart = _cart;
    if (cart == null) return;
    if (!_pickup && _addressId == null) {
      setState(() => _error = 'Choose a delivery address.');
      return;
    }
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      // Priced again from the live menu on the server: what was quoted is what is charged.
      await Api.syncCart(cart.shopId, _lines);
      final order = await Api.placeOrder(
        shopId: cart.shopId,
        addressId: _pickup ? null : _addressId,
        pickup: _pickup,
        method: _method,
        coupon: _applied,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        contactPhone: _pickup ? null : _contactOverride,
        scheduledFor: _slot,
      );
      if (!order.online) {
        _done(order.orderId);
        return;
      }
      if (order.dummy || order.razorpayOrderId == null || order.keyId == null) {
        throw ApiException('Online payment is not available right now. Choose cash ${_pickup ? 'at the shop' : 'on delivery'}.');
      }
      _pending = order;
      final profile = Api.user;
      final email = _email.text.trim().contains('@') ? _email.text.trim() : (profile?.email ?? '');
      _razorpay.open({
        'key': order.keyId,
        'order_id': order.razorpayOrderId,
        'amount': order.amountPaise,
        'name': cart.shopName,
        'description': 'Order via Hyperpik',
        'prefill': {'contact': profile?.phone ?? '', 'email': email},
        'theme': {'color': '#5B21E6'},
      });
    } on ApiException catch (e) {
      if (_wantsPhone(e.message) && await _askPhone()) {
        if (mounted) {
          setState(() => _placing = false);
          _place();
        }
        return;
      }
      if (mounted) {
        setState(() {
          _error = e.message;
          _placing = false;
        });
      }
    }
  }

  Future<void> _onPaid(PaymentSuccessResponse r) async {
    final order = _pending;
    if (order == null) return;
    try {
      await Api.confirmPayment(orderId: order.orderId, paymentId: r.paymentId ?? '', signature: r.signature ?? '');
      _done(order.orderId);
    } on ApiException catch (e) {
      // The money moved but the server could not confirm: say so plainly. The order is found under Orders once it is.
      if (mounted) {
        setState(() {
          _placing = false;
          _error = 'Your payment went through but we could not confirm it yet (${e.message}). Check Orders in a minute; you will not be charged twice.';
        });
      }
    }
  }

  void _onPayError(PaymentFailureResponse r) {
    if (mounted) {
      setState(() {
        _placing = false;
        _error = 'The payment was not completed. You have not been charged. ${r.message ?? ''}'.trim();
      });
    }
  }

  void _done(String orderId) {
    final id = _shopId;
    if (id != null) Cart.instance.clearShop(id);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: orderId, justPlaced: true)));
  }

  // ---- pieces ----------------------------------------------------------------------------------------------------

  Widget _h2(String text, {String? aside}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
          if (aside != null) TextSpan(text: ' · $aside', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.faint(context))),
        ])),
      );

  Widget _radio(bool on) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? Hp.accent : Hp.lineStrong(context), width: on ? 4.5 : 1.5), color: on ? Colors.white : Colors.transparent),
      );

  Widget _choice({required bool on, required VoidCallback onTap, required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(color: on ? Hp.tint(context) : Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? Hp.accent : Hp.line(context), width: 0.8)),
          child: child,
        ),
      );

  Widget _notice(String text, Color c) => Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.withValues(alpha: 0.3), width: 0.8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.warning_amber_rounded, size: 16, color: c)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.43, color: c))),
        ]),
      );

  Widget _stepper(CartLine line) {
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Hp.lineStrong(context), width: 0.8)), child: Icon(icon, size: 12)),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove_rounded, () => Cart.instance.setQuantity(_shopId!, line, line.quantity - 1)),
      SizedBox(width: 24, child: Text('${line.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
      btn(Icons.add_rounded, () => Cart.instance.setQuantity(_shopId!, line, line.quantity + 1)),
    ]);
  }

  /// A few extras from the same shop, one tap each: things people order here, from a category the cart does not have yet,
  /// that need no choice. The same rule as the website's cart.
  Widget _suggestions(ShopCart cart) {
    final shop = _shop;
    if (shop == null || _menu.isEmpty) return const SizedBox.shrink();
    final inCart = {for (final l in cart.lines) l.itemId};
    final haveCats = {for (final i in _menu.where((i) => inCart.contains(i.id))) i.categoryId};
    final avg = cart.lines.isEmpty ? 0 : cart.lines.fold<num>(0, (a, l) => a + l.unitPrice) / cart.lines.length;
    final picks = _menu.where((i) => !inCart.contains(i.id) && i.available && i.price > 0 && !i.needsChoice).toList()
      ..sort((a, b) {
        num score(MenuItem i) => (i.bestseller ? 10 : 0) + (haveCats.contains(i.categoryId) ? 0 : 6) + (avg > 0 && i.price <= avg ? 3 : 0);
        final d = score(b).compareTo(score(a));
        return d != 0 ? d : a.price.compareTo(b.price);
      });
    final shown = picks.take(4).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final catKey = shop.categoryKey;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Add to your order', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      SizedBox(
        height: 186,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: shown.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, k) {
            final it = shown[k];
            return Container(
              width: 150,
              clipBehavior: Clip.antiAlias,
              decoration: cardDecoration(context),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 84,
                  width: double.infinity,
                  child: ColoredBox(color: Hp.surface2(context), child: Image.network(Media.item(catKey, it.id, it.imageUrl), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text('₹${it.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      InkWell(
                        onTap: () => Cart.instance.add(shop, it),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(border: Border.all(color: Hp.accent), borderRadius: BorderRadius.circular(8)),
                          child: Text('ADD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Hp.accent)),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  Widget _lineCard(ShopCart cart) {
    final catKey = _shop?.categoryKey ?? '';
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(context),
      child: Column(children: [
        for (var i = 0; i < cart.lines.length; i++)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: Hp.line(context), width: 0.8))),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ColoredBox(color: Hp.surface2(context), child: Image.network(Media.item(catKey, cart.lines[i].itemId, cart.lines[i].imageUrl), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: cart.lines[i].name, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                    if (cart.lines[i].optionNames.isNotEmpty) TextSpan(text: ' · ${cart.lines[i].optionNames.join(' · ')}', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.faint(context))),
                  ])),
                  const SizedBox(height: 4),
                  Text('₹${cart.lines[i].total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, height: 1.43)),
                ]),
              ),
              const SizedBox(width: 12),
              _stepper(cart.lines[i]),
              const SizedBox(width: 12),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Cart.instance.setQuantity(_shopId!, cart.lines[i], 0),
                child: const SizedBox(width: 32, height: 32, child: Icon(Icons.delete_outline_rounded, size: 16, color: Hp.bad)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _offerRow(OfferInfo o) {
    final ref = o.couponId ?? o.code;
    final applied = ref != null && ref == _applied;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: applied ? Hp.ok.withValues(alpha: 0.05) : Hp.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: applied ? Hp.ok : (o.eligible ? Hp.line(context) : Hp.line(context).withValues(alpha: 0.6)), width: 0.8),
      ),
      child: Opacity(
        opacity: o.eligible ? 1 : 0.6,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.sell_outlined, size: 16, color: Hp.accent)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.title, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
              if ((o.subtitle ?? '').isNotEmpty) Text(o.subtitle!, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  o.eligible ? (applied ? 'Applied — you saved ₹${o.discount.toStringAsFixed(0)}' : 'Save ₹${o.discount.toStringAsFixed(0)} on this order') : (o.reason ?? ''),
                  style: TextStyle(fontSize: 13, height: 1.33, color: o.eligible ? Hp.ok : Hp.faint(context)),
                ),
              ),
            ]),
          ),
          if (o.eligible && ref != null) ...[
            const SizedBox(width: 12),
            if (applied)
              InkWell(onTap: _clearOffer, child: const Text('Remove', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: Hp.bad)))
            else
              SizedBox(
                height: 28,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 28), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  onPressed: () => _applyOffer(o),
                  child: const Text('Apply'),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Widget _offers_() {
    final rows = [..._offers.where((o) => o.eligible), ..._offers.where((o) => !o.eligible)];
    final shown = _offersExpanded ? rows : rows.take(2).toList();
    final inList = _applied != null && _offers.any((o) => (o.couponId ?? o.code) == _applied);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _h2('Offers & coupons'),
        if (rows.isNotEmpty) ...[
          for (final o in shown) _offerRow(o),
          if (rows.length > 2)
            Center(
              child: InkWell(
                onTap: () => setState(() => _offersExpanded = !_offersExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_offersExpanded ? 'Show less' : 'See ${rows.length - 2} more offer${rows.length - 2 == 1 ? '' : 's'}', style: const TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: Hp.accent)),
                    const SizedBox(width: 4),
                    Icon(_offersExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 14, color: Hp.accent),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(isDense: true, hintText: 'Have a coupon code?', hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                onSubmitted: (_) => _applyCode(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _applyCode, child: const Text('Apply')),
        ]),
        if (_applied != null && !inList)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text('${_appliedTitle != null ? '$_appliedTitle applied — ' : ''}You saved ₹${(_quote?.discount ?? 0).toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.ok))),
              InkWell(onTap: _clearOffer, child: Icon(Icons.close_rounded, size: 14, color: Hp.faint(context))),
            ]),
          ),
        if (_couponError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_couponError!, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.bad))),
      ]),
    );
  }

  Widget _howSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _h2('How would you like it?'),
        Row(children: [
          for (final f in const [(false, 'Delivery', 'To your address'), (true, 'Pickup', 'Collect it from the shop')]) ...[
            Expanded(
              child: _choice(
                on: _pickup == f.$1,
                padding: const EdgeInsets.all(12),
                onTap: () {
                  if (_pickup == f.$1) return;
                  setState(() {
                    _pickup = f.$1;
                    _quote = null;
                    _error = null;
                  });
                  _price();
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.$2, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(f.$3, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
                ]),
              ),
            ),
            if (!f.$1) const SizedBox(width: 8),
          ],
        ]),
      ]),
    );
  }

  /// "As soon as possible" or "Schedule for later" with today's times. Hidden when the shop has none left today.
  Widget _whenSection() {
    final slots = _quote?.slots ?? const <DateTime>[];
    if (slots.isEmpty) return const SizedBox.shrink();
    final later = _slot != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _h2(_pickup ? 'When do you want to collect it?' : 'When do you want it delivered?'),
        Row(children: [
          for (final w in const [(false, 'As soon as possible', 'Now'), (true, 'Schedule for later', 'Pick a time today')]) ...[
            Expanded(
              child: _choice(
                on: later == w.$1,
                padding: const EdgeInsets.all(12),
                onTap: () => setState(() => _slot = w.$1 ? (_slot ?? slots.first) : null),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.$2, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(w.$3, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
                ]),
              ),
            ),
            if (!w.$1) const SizedBox(width: 8),
          ],
        ]),
        if (later)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in slots)
                ChoiceChip(
                  label: Text(istTime(s)),
                  selected: s.isAtSameMomentAs(_slot!),
                  onSelected: (_) => setState(() => _slot = s),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _whereSection() {
    final cart = _cart!;
    if (_pickup) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _h2('Pick up from'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context), width: 0.8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_quote?.pickupShop ?? cart.shopName, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
              if ((_quote?.pickupAddress ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(_quote!.pickupAddress!, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context)))),
              Padding(padding: const EdgeInsets.only(top: 8), child: Text("We'll message you on WhatsApp the moment your order is ready to collect.", style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context)))),
            ]),
          ),
        ]),
      );
    }
    final list = _addresses;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _h2('Delivery address'),
        if (list == null)
          const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
        else ...[
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _choice(
                on: _addressId == a.id,
                onTap: () {
                  setState(() {
                    _addressId = a.id;
                    _contactOverride = null;
                  });
                  _price();
                },
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 3), child: _radio(_addressId == a.id)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(a.fullAddress, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
                      AwayNote(a, fontSize: 13),
                    ]),
                  ),
                ]),
              ),
            ),
          if (_address != null) _contactCard(),
          if (list.isEmpty)
            SizedBox(width: double.infinity, height: 48, child: FilledButton(style: FilledButton.styleFrom(textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), onPressed: _addAddress, child: const Text('Add a delivery address')))
          else
            Padding(padding: const EdgeInsets.only(top: 4), child: InkWell(onTap: _addAddress, child: const Text('+ Add a new address', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.accent)))),
        ],
      ]),
    );
  }

  /// The number the rider will ring for this delivery: the address's own contact if it has one, else the account's.
  String? get _contactPhone {
    final raw = _contactOverride ?? _address?.contactPhone ?? Api.user?.phone;
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : null;
  }

  /// Asked before paying rather than found out after: who gets the call, with a way to change it for someone else's
  /// door. For this order only; the saved address is left as it is.
  Widget _contactCard() {
    final phone = _contactPhone;
    if (phone == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(context),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('The rider will call', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w600, color: Hp.muted(context))),
            Text('+91 ${phone.substring(0, 5)} ${phone.substring(5)}', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
            if (_contactOverride != null) Text('Just for this order', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context))),
          ]),
        ),
        TextButton(onPressed: _changeContact, child: const Text('Change')),
      ]),
    );
  }

  Future<void> _changeContact() async {
    final c = TextEditingController();
    String? problem;
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Who should the rider call?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(prefixText: '+91  ', hintText: '10-digit mobile number', errorText: problem),
            ),
            const SizedBox(height: 8),
            Text('Just for this order. Your saved address stays as it is.', style: TextStyle(fontSize: 13, color: Hp.faint(ctx))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final digits = c.text.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) {
                  setLocal(() => problem = 'Enter a valid 10-digit mobile number.');
                  return;
                }
                Navigator.pop(ctx, digits.substring(digits.length - 10));
              },
              child: const Text('Use this number'),
            ),
          ],
        ),
      ),
    );
    if (entered != null && mounted) setState(() => _contactOverride = entered);
  }

  Future<void> _addAddress() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddAddressScreen(firstAddress: (_addresses ?? const []).isEmpty)));
    if (added == true) _loadAddresses();
  }

  Widget _emailSection() => Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _h2('Email', aside: 'optional'),
          SizedBox(
            height: 44,
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(isDense: true, hintText: 'you@example.com', hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('For your payment receipt. You can change it on the payment screen too.', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context)))),
        ]),
      );

  Widget _paymentSection() => Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _h2('Payment'),
          for (final m in [
            ('razorpay', Icons.credit_card_outlined, 'UPI / Card / Netbanking', 'Razorpay'),
            ('cod', Icons.payments_outlined, _pickup ? 'Pay at the shop' : 'Cash on delivery', 'Pay when it arrives'),
          ].where((m) => (_quote?.paymentMethods ?? const ['razorpay']).contains(m.$1)))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _choice(
                on: _method == m.$1,
                onTap: () {
                  setState(() => _method = m.$1);
                  _price();
                },
                child: Row(children: [
                  _radio(_method == m.$1),
                  const SizedBox(width: 12),
                  Icon(m.$2, size: 16, color: Hp.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: m.$3, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                      TextSpan(text: '  ${m.$4}', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context))),
                    ])),
                  ),
                ]),
              ),
            ),
        ]),
      );

  Widget _noteSection() => Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _h2('Note for the store'),
          TextField(
            controller: _note,
            maxLines: 2,
            minLines: 2,
            maxLength: 200,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(counterText: '', hintText: 'e.g. Leave at door, ring the bell', hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          ),
        ]),
      );

  Widget _summary(ShopCart cart, bool closed) {
    final q = _quote;
    Widget row(Widget label, Widget value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: label), const SizedBox(width: 12), value]));
    Text plain(String t, {Color? color, FontWeight? w, TextDecoration? deco}) => Text(t, style: TextStyle(fontSize: 14, height: 1.43, color: color, fontWeight: w, decoration: deco));
    final muted = Hp.muted(context);
    final faint = Hp.faint(context);
    final total = q?.total;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(bottom: 16), child: Text('Order summary', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
        row(plain('Item total', color: muted), plain('₹${(q?.subtotal ?? cart.subtotal).toStringAsFixed(0)}')),
        if (q != null) ...[
          if (_pickup)
            row(plain('Delivery', color: muted), plain('Not needed, you collect', color: faint))
          else
            row(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                plain('Delivery', color: muted),
                if (q.etaNote != null) Text(q.etaNote!, style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
                if (q.deliveryVendorPays > 0) Text(q.deliveryFee == 0 ? 'Store covers delivery' : 'Store covers ₹${q.deliveryVendorPays.toStringAsFixed(0)} of delivery', style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.ok)),
              ]),
              q.deliveryVendorPays > 0
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('₹${q.deliveryGross.toStringAsFixed(0)}', style: TextStyle(fontSize: 14, height: 1.43, color: faint, decoration: TextDecoration.lineThrough)),
                      const SizedBox(width: 6),
                      plain(q.deliveryFee == 0 ? 'FREE' : '₹${q.deliveryFee.toStringAsFixed(0)}', color: q.deliveryFee == 0 ? Hp.ok : null, w: FontWeight.w600),
                    ])
                  : plain(q.deliveryFee == 0 ? 'FREE' : '₹${q.deliveryFee.toStringAsFixed(0)}', color: q.deliveryFee == 0 ? Hp.ok : null, w: q.deliveryFee == 0 ? FontWeight.w600 : null),
            ),
          if (q.tax > 0) row(plain('Taxes', color: muted), plain('₹${q.tax.toStringAsFixed(2)}')),
          if (q.packing > 0) row(plain('Packing', color: muted), plain('₹${q.packing.toStringAsFixed(2)}')),
          if (q.handling > 0 || q.handlingWaived)
            row(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                plain(_pickup ? 'Pickup service fee' : 'Handling', color: muted),
                if (q.handlingWaived && q.handlingWaivedText != null) Text(q.handlingWaivedText!, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.ok)),
              ]),
              q.handlingWaived
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('₹${q.handlingSaved.toStringAsFixed(0)}', style: TextStyle(fontSize: 14, height: 1.43, color: faint, decoration: TextDecoration.lineThrough)),
                      const SizedBox(width: 6),
                      plain('FREE', color: Hp.ok, w: FontWeight.w600),
                    ])
                  : plain('₹${q.handling.toStringAsFixed(2)}'),
            ),
          if (q.paymentFee > 0) row(plain('Payment fee', color: muted), plain('₹${q.paymentFee.toStringAsFixed(2)}')),
          if (q.discount > 0) row(plain(_appliedTitle ?? 'Offer applied', color: Hp.ok), plain('−₹${q.discount.toStringAsFixed(0)}', color: Hp.ok)),
        ],
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Hp.line(context), width: 0.8))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600)),
            Text(total == null ? (_pricing ? '…' : '—') : '₹${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(fontSize: 14, height: 1.43, color: Hp.bad))),
      ]),
    );
  }

  /// The pay button, pinned to the bottom of the screen so it is always in reach however far the page is scrolled, with the
  /// total beside it. Any error ("Choose a delivery address", a refused order) shows here too, since the summary it also
  /// appears in can be far off screen.
  Widget _payBar(bool closed) {
    final q = _quote;
    final total = q?.total;
    final canPay = !closed && !_placing && !_pricing && q != null && (_pickup || _addressId != null);
    final label = closed ? 'Store is closed' : _placing ? 'Placing order…' : _method == 'cod' ? 'Place order' : (total == null ? 'Pay' : 'Pay ₹${total.toStringAsFixed(2)}');
    return Material(
      color: Hp.surface(context),
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.bad))),
            Row(children: [
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Total', style: TextStyle(fontSize: 12, height: 1.2, color: Hp.muted(context))),
                const SizedBox(height: 2),
                Text(total == null ? (_pricing ? '…' : '—') : '₹${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, height: 1.2, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    onPressed: canPay ? _place : null,
                    child: Text(label),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ---- the page --------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final carts = Cart.instance.carts;
    if (carts.isEmpty || _cart == null) {
      return SitePage(
        bottom: 40,
        children: [
          const SizedBox(height: 8),
          EmptyCard(
            icon: Icons.shopping_bag_outlined,
            title: 'Your cart is empty',
            body: 'Browse neighbourhood stores and add something you love.',
            actionLabel: 'Browse stores',
            onAction: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              shellTab.value = tabHome;
            },
          ),
        ],
      );
    }
    final cart = _cart!;
    final signedIn = Api.user != null;
    final closed = _shop != null && !_shop!.canOrder;
    final closedText = _shop == null ? null : (!_shop!.open ? (_shop!.closedReason ?? "This store isn't accepting orders right now") : 'This shop does not deliver to your location');
    final offersPickup = _quote?.pickupOffered ?? true;
    if (!offersPickup && _pickup) _pickup = false;

    return SitePage(
      bottom: 40,
      // Signed-in shoppers get the pay button pinned to the bottom of the screen; the log-in card has nothing to pay yet.
      bottomBar: signedIn ? _payBar(closed) : null,
      onAuthChanged: () {
        setState(() {});
        _loadAddresses();
      },
      children: [
        if (carts.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SizedBox(
              height: 28,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in carts)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _switchTo(c.shopId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.shopId == _shopId ? Hp.tint(context) : null,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: c.shopId == _shopId ? Hp.accent : Hp.line(context), width: 0.8),
                        ),
                        child: Text(c.shopName, style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: c.shopId == _shopId ? Hp.accentHi : Hp.muted(context))),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        const Text('Your bag', style: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
        const SizedBox(height: 8),
        const Text('Cart & checkout', style: TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.75)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text.rich(TextSpan(style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context)), children: [
            const TextSpan(text: 'Sold by '),
            TextSpan(text: cart.shopName, style: TextStyle(fontWeight: FontWeight.w600, color: Hp.text(context))),
            const TextSpan(text: ' — Hyperpik collects payment on their behalf.'),
          ])),
        ),
        if (closed && closedText != null) _notice('$closedText. Your items are still here, so come back once the store reopens.', Hp.bad),
        Padding(padding: const EdgeInsets.only(bottom: 16), child: _lineCard(cart)),
        _suggestions(cart),
        const SizedBox(height: 16),
        if (!signedIn)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: cardDecoration(context),
            child: Column(children: [
              Text('Log in to check out', style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Your bag is saved on this phone. Sign in to pick an address and pay.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignInScreen(popOnSuccess: true))).then((_) {
                  if (mounted) {
                    setState(() {});
                    _loadAddresses();
                  }
                }),
                child: const Text('Log in'),
              ),
            ]),
          )
        else ...[
          _offers_(),
          if (offersPickup) _howSection(),
          _whenSection(),
          _whereSection(),
          _emailSection(),
          _paymentSection(),
          _noteSection(),
          _summary(cart, closed),
        ],
      ],
    );
  }
}
