import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/cart.dart';
import '../../core/cart_dock.dart';
import '../../core/media.dart';
import '../../core/nav.dart';
import '../../core/orders_models.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import '../support/issue_screen.dart';
import 'live_map.dart';

/// One order, as the website's order page has it: a confirmation, the order's own card, where it is (a timeline, a live
/// map once a rider has it), what is in it, the bill, a rating once it is delivered, and a way to get help.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.justPlaced = false});
  final String orderId;
  final bool justPlaced;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  OrderDetail? _order;
  String? _error;
  Timer? _timer;
  bool _confirmingCancel = false;
  bool _cancelling = false;
  String? _cancelError;
  final _cancelReason = TextEditingController();
  bool _reordering = false;
  int _stars = 0;
  bool _editingReview = false;
  final _comment = TextEditingController();
  bool _rating = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) {
      final o = _order;
      if (o == null || o.isActive || (o.refund != null && o.refund!.state == 'processing')) _load();
    });
    if (widget.justPlaced) HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _comment.dispose();
    _cancelReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await Api.order(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = o;
        _error = null;
        if (o.reviewRating != null && _stars == 0) {
          _stars = o.reviewRating!;
          _comment.text = o.reviewComment ?? '';
        }
      });
    } on ApiException catch (e) {
      if (mounted && _order == null) setState(() => _error = e.message);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _cancelling = true;
      _cancelError = null;
    });
    try {
      await Api.cancelOrder(widget.orderId, _cancelReason.text.trim().isEmpty ? 'Cancelled by customer' : _cancelReason.text.trim());
      setState(() => _confirmingCancel = false);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _cancelError = e.message);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  /// Puts the same dishes back in the cart at today's prices and takes the customer there.
  Future<void> _reorder() async {
    setState(() => _reordering = true);
    try {
      await reorderOrder(context, widget.orderId);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _sendReview() async {
    if (_stars == 0) return;
    setState(() => _rating = true);
    try {
      await Api.review(widget.orderId, _stars, _comment.text.trim());
      HapticFeedback.mediumImpact();
      setState(() => _editingReview = false);
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _rating = false);
    }
  }

  // ---- small helpers ----------------------------------------------------------------------------------------------

  Widget _h2(String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(text, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)));

  /// "Cash on delivery · paid", "Paid online · ₹x refunded": the customer's side of the payment state.
  String _paymentLabel(OrderDetail o) {
    if (o.paymentMethod == 'cod') {
      if (o.isDineIn) return o.paymentStatus == 'paid' ? 'Paid at the table' : 'Pay at the table';
      return o.paymentStatus == 'paid' ? 'Cash on delivery · paid' : 'Cash on delivery';
    }
    switch (o.paymentStatus) {
      case 'paid':
        final refunded = o.refund?.amount ?? 0;
        return refunded > 0 ? 'Paid online · ₹${refunded.toStringAsFixed(0)} refunded' : 'Paid online';
      case 'refunded':
        return o.refund != null ? 'Refunded ₹${o.refund!.amount.toStringAsFixed(2)}' : 'Refunded';
      case 'failed':
        return 'Payment failed — this order was not placed';
      case 'pending':
        return "Payment not completed — this order won't be prepared";
      default:
        return o.paymentStatus;
    }
  }

  bool _paymentNeverWentThrough(OrderDetail o) => o.paymentStatus == 'pending' || o.paymentStatus == 'failed';

  (double, double)? _pt(double? a, double? b) => a == null || b == null ? null : (a, b);

  // ---- the page ---------------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final o = _order;
    if (_error != null) {
      return SitePage(bottom: 40, children: [Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Column(children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 14), FilledButton(onPressed: _load, child: const Text('Try again'))]))]);
    }
    if (o == null) {
      return const SitePage(bottom: 40, children: [Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))]);
    }
    final muted = Hp.muted(context);
    final faint = Hp.faint(context);
    final badPay = _paymentNeverWentThrough(o);
    return SitePage(
      onRefresh: _load,
      bottom: 40,
      children: [
        if (widget.justPlaced && !badPay && !o.isCancelled) _confirmedCard(o),
        _orderCard(o, muted, faint, badPay),
        if (o.isCancelled) _cancelledCard(o),
        if (o.refund != null) _RefundCard(info: o.refund!, orderId: o.id),
        _h2('Track your order'),
        Padding(padding: const EdgeInsets.only(bottom: 32), child: _tracking(o)),
        _h2('Items'),
        _itemsCard(o),
        _billCard(o, badPay),
        if (o.canReview) _rateCard(o),
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IssueScreen(orderId: o.id, orderNumber: o.number))), child: const Text('Report an issue with this order')),
            if (o.status == 'delivered' || o.isCancelled) OutlinedButton(onPressed: _reordering ? null : _reorder, child: Text(_reordering ? 'Adding…' : 'Order again')),
          ]),
        ),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                shellTab.value = tabOrders;
              },
              child: const Text('All orders'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                shellTab.value = tabHome;
              },
              child: const Text('Continue shopping'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _confirmedCard(OrderDetail o) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(32),
        decoration: cardDecoration(context),
        child: Column(children: [
          Container(width: 64, height: 64, decoration: const BoxDecoration(color: Hp.ok, shape: BoxShape.circle), child: const Icon(Icons.check_circle_outline_rounded, size: 32, color: Colors.white)),
          const SizedBox(height: 16),
          const Text('Order Confirmed!', style: TextStyle(fontSize: 24, height: 1.33, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          const SizedBox(height: 4),
          Text('Thanks for ordering from ${o.shopName}.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
        ]),
      );

  Widget _orderCard(OrderDetail o, Color muted, Color faint, bool badPay) {
    final deadline = o.createdAt.add(const Duration(minutes: 2));
    final inWindow = badPay || DateTime.now().isBefore(deadline);
    final beforeReady = const {'placed', 'accepted', 'processing'}.contains(o.status);
    final showCancel = o.canCancel && inWindow && beforeReady && !o.isCancelled;
    final prepaid = o.paymentMethod != 'cod' && !badPay;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Order ${o.number}', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
          Text(DateFormat('d/M/yyyy, h:mm:ss a').format(o.createdAt).toLowerCase(), style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
        ]),
        const SizedBox(height: 8),
        Text(o.isDineIn ? 'Dining in at ${o.shopName}${o.tableLabel == null ? '' : ' · ${o.tableLabel!.replaceFirstMapped(RegExp(r'^(table)(\d)', caseSensitive: false), (m) => '${m[1]} ${m[2]}')}'}' : o.isPickup || o.addressFull == null ? 'Collect from the shop' : 'Delivering to ${o.addressLabel ?? ''} — ${o.addressFull}', style: TextStyle(fontSize: 14, height: 1.43, color: muted)),
        const SizedBox(height: 4),
        Text(_paymentLabel(o), style: TextStyle(fontSize: 13, height: 1.33, fontWeight: badPay ? FontWeight.w500 : FontWeight.w500, color: badPay ? Hp.bad : faint)),
        if (showCancel) ...[
          const SizedBox(height: 12),
          if (!_confirmingCancel)
            InkWell(
              onTap: () => setState(() => _confirmingCancel = true),
              child: Text(badPay ? 'Remove this order' : 'Cancel order', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.bad)),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.bad.withValues(alpha: 0.3), width: 0.8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.warning_amber_rounded, size: 16, color: Hp.bad)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(badPay ? 'Remove this order?' : 'Cancel this order?', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.bad))),
                ]),
                const SizedBox(height: 12),
                Text(
                  badPay
                      ? 'Payment never went through for this one, so nothing was charged — removing it just clears it from your order history.'
                      : prepaid
                          ? 'A small cancellation charge is kept by Hyperpik, and the payment fee the payment processor does not return is deducted. The rest of your ₹${o.total.toStringAsFixed(2)} comes back to you.'
                          : 'Nothing was charged yet — cancelling has no fee.',
                  style: TextStyle(fontSize: 13, height: 1.33, color: muted),
                ),
                const SizedBox(height: 12),
                TextField(controller: _cancelReason, style: const TextStyle(fontSize: 14), decoration: InputDecoration(isDense: true, hintText: 'Reason (optional)', hintStyle: TextStyle(fontSize: 14, color: faint), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10))),
                if (_cancelError != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_cancelError!, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.bad))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _cancelling ? null : () => setState(() => _confirmingCancel = false), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(vertical: 8)), child: const Text('Never mind'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _cancelling ? null : _cancel,
                      style: FilledButton.styleFrom(backgroundColor: Hp.bad, minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text(_cancelling ? (badPay ? 'Removing…' : 'Cancelling…') : (badPay ? 'Remove order' : 'Confirm cancellation')),
                    ),
                  ),
                ]),
              ]),
            ),
        ] else if (!o.isCancelled && o.isActive && o.cannotCancelReason != null) ...[
          const SizedBox(height: 12),
          Text(o.cannotCancelReason!, style: TextStyle(fontSize: 13, height: 1.33, color: faint)),
        ],
      ]),
    );
  }

  Widget _cancelledCard(OrderDetail o) {
    final bySelf = (o.cancelledLabel ?? '').toLowerCase().contains('you');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Hp.bad.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.bad.withValues(alpha: 0.2), width: 0.8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!bySelf) ...[const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.sentiment_dissatisfied_outlined, size: 20, color: Hp.bad)), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bySelf ? 'Order cancelled' : "We're sorry — this order was cancelled", style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, color: Hp.bad)),
            const SizedBox(height: 4),
            Text(o.cancelledDetail ?? o.cancelledLabel ?? (bySelf ? 'You cancelled this order.' : '${o.shopName} had to cancel this order.'), style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
          ]),
        ),
      ]),
    );
  }

  // ---- tracking ---------------------------------------------------------------------------------------------------

  /// A table order: the three steps, the table, and what is left to pay. No rider, no PIN, no arrival time.
  Widget _dineIn(OrderDetail o) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (o.tableLabel != null) ...[
        _Panel(
          icon: Icons.restaurant_rounded,
          title: 'Your table',
          child: Text(o.tableLabel!.replaceFirstMapped(RegExp(r'^(table)(\d)', caseSensitive: false), (m) => '${m[1]} ${m[2]}'),
              style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 16),
      ],
      if (o.isCancelled) _cancelledTimeline(o) else _Timeline(steps: o.steps),
      if (!o.isCancelled && o.amountDue > 0) ...[
        const SizedBox(height: 16),
        _Panel(
          icon: Icons.payments_outlined,
          title: 'Pay at the table',
          child: Text('Pay when you are done. Ask the staff for the bill.', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
        ),
      ],
    ]);
  }

  Widget _tracking(OrderDetail o) {
    if (o.isPickup) return _PickupPanel(order: o);
    if (o.isDineIn) return _dineIn(o);
    final steps = o.steps;
    final hasRider = o.riderName != null || o.riderPhone != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (o.estimateFrom != null && o.estimateTo != null && o.isActive) ...[_EtaBanner(order: o), const SizedBox(height: 16)],
      if (o.isCancelled)
        _cancelledTimeline(o)
      else
        _Timeline(steps: steps),
      if (o.status != 'cancelled' && o.status != 'delivered') ...[
        if (o.status != 'placed' && o.deliveryOtp != null) ...[const SizedBox(height: 32), _PinCard(pin: o.deliveryOtp!)],
        const SizedBox(height: 32),
        if (!hasRider)
          _Panel(icon: Icons.sync_rounded, title: 'Finding you a rider', child: Text('We book a delivery partner shortly before your food is ready, so they arrive as it does.', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))))
        else ...[
          _Panel(
            icon: Icons.two_wheeler_rounded,
            title: o.riderName != null ? '${o.riderName} is your rider' : 'A rider is assigned',
            child: o.riderPhone == null
                ? const SizedBox.shrink()
                : InkWell(
                    onTap: () => launchUrl(Uri.parse('tel:${o.riderPhone}')),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.phone_outlined, size: 14, color: Hp.accent),
                        const SizedBox(width: 6),
                        Text(o.riderPhone!, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.accent)),
                      ]),
                    ),
                  ),
          ),
          if (o.dropLat != null || o.shopLat != null) ...[
            const SizedBox(height: 12),
            LiveMap(shop: _pt(o.shopLat, o.shopLng), drop: _pt(o.dropLat, o.dropLng), rider: _pt(o.riderLat, o.riderLng), shopName: o.shopName),
          ],
        ],
      ],
    ]);
  }

  Widget _cancelledTimeline(OrderDetail o) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: cardDecoration(context),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(o.cancelledLabel ?? 'Order cancelled', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, color: Hp.bad)),
          if (o.cancelledDetail != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(o.cancelledDetail!, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context)))),
        ]),
      );

  // ---- items and bill ---------------------------------------------------------------------------------------------

  Widget _itemsCard(OrderDetail o) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        decoration: cardDecoration(context),
        child: Column(children: [
          for (var i = 0; i < o.items.length; i++)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: Hp.line(context), width: 0.8))),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 56, height: 56, child: ColoredBox(color: Hp.surface2(context), child: CachedNetworkImage(imageUrl: Media.item('food', o.items[i].name), fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox.shrink()))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14, height: 1.43), children: [
                          TextSpan(text: '${o.items[i].quantity}× ${o.items[i].name}'),
                          if (o.items[i].variation != null) TextSpan(text: ' (${o.items[i].variation})', style: TextStyle(color: Hp.faint(context))),
                        ])),
                      ),
                      const SizedBox(width: 12),
                      Text('₹${o.items[i].lineTotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500)),
                    ]),
                    if (o.items[i].addons.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(o.items[i].addons.join(', '), style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context)))),
                  ]),
                ),
              ]),
            ),
        ]),
      );

  Widget _billCard(OrderDetail o, bool badPay) {
    Widget row(String l, String v, {Color? color, Color? labelColor}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l, style: TextStyle(fontSize: 14, height: 1.43, color: labelColor ?? Hp.muted(context))),
            Text(v, style: TextStyle(fontSize: 14, height: 1.43, color: color)),
          ]),
        );
    final b = o.bill;
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(context),
      child: Column(children: [
        row('Item total', '₹${(b['subtotal'] ?? 0).toStringAsFixed(0)}'),
        if (!o.isDineIn) row('Delivery', '₹${(b['delivery'] ?? 0).toStringAsFixed(0)}'),
        row('Taxes', '₹${(b['tax'] ?? 0).toStringAsFixed(0)}'),
        if ((b['packing'] ?? 0) > 0) row('Packing', '₹${b['packing']!.toStringAsFixed(0)}'),
        if ((b['handling'] ?? 0) > 0) row('Handling', '₹${b['handling']!.toStringAsFixed(0)}'),
        if ((b['discount'] ?? 0) > 0) row('Discount', '−₹${b['discount']!.toStringAsFixed(0)}', color: Hp.ok, labelColor: Hp.ok),
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Hp.line(context), width: 0.8))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(badPay ? 'Order total' : 'Total paid', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
            Text('₹${o.total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]),
    );
  }

  Widget _rateCard(OrderDetail o) {
    final saved = o.reviewRating != null;
    if (saved && !_editingReview) {
      return Container(
        margin: const EdgeInsets.only(bottom: 32),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Hp.ok.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.ok.withValues(alpha: 0.3), width: 0.8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_outline_rounded, size: 24, color: Hp.ok)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Thank you for rating ${o.shopName}!', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(children: [for (var n = 1; n <= 5; n++) Icon(n <= o.reviewRating! ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: n <= o.reviewRating! ? Hp.star : Hp.lineStrong(context))]),
              if ((o.reviewComment ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('“${o.reviewComment}”', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context)))),
            ]),
          ),
          InkWell(onTap: () => setState(() => _editingReview = true), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.edit_outlined, size: 12, color: Hp.accent), SizedBox(width: 4), Text('Edit', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: Hp.accent))])),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(saved ? 'Change your rating' : 'How was your order from ${o.shopName}?', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          for (var n = 1; n <= 5; n++)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _stars = n);
              },
              child: Padding(padding: const EdgeInsets.all(2), child: Icon(n <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 28, color: n <= _stars ? Hp.star : Hp.lineStrong(context))),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _comment, maxLines: 2, minLines: 2, maxLength: 300, style: const TextStyle(fontSize: 14), decoration: InputDecoration(counterText: '', hintText: "Anything you'd like the store to know? (optional)", hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10))),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton(onPressed: _rating || _stars == 0 ? null : _sendReview, child: Text(_rating ? 'Saving…' : saved ? 'Update rating' : 'Submit rating')),
          if (saved) ...[const SizedBox(width: 12), TextButton(onPressed: () => setState(() => _editingReview = false), style: TextButton.styleFrom(foregroundColor: Hp.muted(context)), child: const Text('Cancel'))],
        ]),
      ]),
    );
  }
}

// ---- pieces of the tracking view --------------------------------------------------------------------------------------

/// "Arriving by 7:40 – 7:50 pm", at the top of an order that is still on its way.
class _EtaBanner extends StatelessWidget {
  const _EtaBanner({required this.order});
  final OrderDetail order;

  static String _clock(DateTime t) => DateFormat('h:mm a').format(t).toLowerCase();

  @override
  Widget build(BuildContext context) {
    final from = order.estimateFrom!;
    final to = order.estimateTo!;
    final mid = from.add(to.difference(from) ~/ 2);
    final left = mid.difference(DateTime.now()).inMinutes;
    final basis = switch (order.estimateBasis) {
      'waiting_for_shop' => 'Starts once the shop accepts your order.',
      'on_the_way' => 'Your rider is on the way to you.',
      _ => 'Your food is being prepared, then a rider brings it.',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Hp.tint(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.accent.withValues(alpha: 0.3), width: 0.8)),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: Hp.accent, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 24)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ESTIMATED ARRIVAL', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: Hp.faint(context))),
            Text('${_clock(from)} – ${_clock(to)}', style: const TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            Text('${left <= 3 ? 'Any minute now. ' : 'About $left min. '}$basis', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
          ]),
        ),
      ]),
    );
  }
}

/// The steps of the order in one card: a green tick for each that has happened, a line joining them.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});
  final List<OrderStep> steps;

  @override
  Widget build(BuildContext context) {
    final lastReached = steps.lastIndexWhere((s) => s.reached);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(context),
      child: Column(children: [
        for (var i = 0; i < steps.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(border: i == steps.length - 1 ? null : Border(bottom: BorderSide(color: Hp.line(context), width: 0.8))),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Column(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[i].reached ? Hp.ok : null,
                      border: steps[i].reached ? null : Border.all(color: Hp.lineStrong(context), width: 0.8),
                      boxShadow: i == lastReached ? [BoxShadow(color: Hp.ok.withValues(alpha: 0.15), spreadRadius: 4)] : null,
                    ),
                    child: steps[i].reached ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                  ),
                  if (i < steps.length - 1) Expanded(child: Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 4), constraints: const BoxConstraints(minHeight: 20), color: steps[i].reached ? Hp.ok : Hp.line(context))),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
                      Text(steps[i].label, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: steps[i].reached ? FontWeight.w500 : FontWeight.w500, color: steps[i].reached ? null : Hp.faint(context))),
                      if (steps[i].at != null) Text(DateFormat('d MMM, hh:mm a').format(steps[i].at!), style: TextStyle(fontSize: 12, height: 1.45, color: Hp.faint(context))),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({required this.pin});
  final String pin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Hp.tint(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.accent.withValues(alpha: 0.3), width: 0.8)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.key_outlined, size: 14), SizedBox(width: 6), Text('Your delivery PIN', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))]),
            const SizedBox(height: 2),
            Text('Give this PIN to the delivery person when your order is in your hands, and only then.', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
          ]),
        ),
        const SizedBox(width: 16),
        Text(pin, style: const TextStyle(fontFamily: 'monospace', fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: 7.5, color: Hp.accent)),
      ]),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context), width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(color: Hp.tint(context), shape: BoxShape.circle), child: Icon(icon, size: 16, color: Hp.accent)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500))),
        ]),
        Padding(padding: const EdgeInsets.only(left: 36, top: 6), child: child),
      ]),
    );
  }
}

/// The customer's pickup pass: the ready card, the code to tell the shop, the stages, where to go and what to pay.
class _PickupPanel extends StatelessWidget {
  const _PickupPanel({required this.order});
  final OrderDetail order;

  static const _stages = [
    ('Order placed', 'Waiting for the shop to accept it.'),
    ('Being prepared', 'The shop has accepted it and is getting it ready.'),
    ('Ready for pickup', 'Come and collect it. Tell the shop your pickup code.'),
    ('Collected', 'Enjoy!'),
  ];

  int get _current => switch (order.status) {
        'delivered' => 3,
        'ready_for_pickup' => 2,
        'accepted' || 'processing' => 1,
        _ => 0,
      };

  Future<void> _directions() async {
    final o = order;
    final uri = o.pickupLat != null && o.pickupLng != null
        ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${o.pickupLat},${o.pickupLng}')
        : Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${o.pickupShopName ?? o.shopName} ${o.pickupAddress ?? ''}')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (o.isCancelled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Hp.bad.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.bad.withValues(alpha: 0.3), width: 0.8)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.cancel_outlined, size: 24, color: Hp.bad),
          const SizedBox(width: 12),
          Expanded(child: Text('This order was cancelled', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
        ]),
      );
    }
    final cur = _current;
    final ready = cur == 2;
    final showPass = o.pickupCode != null && cur >= 1 && cur < 3;
    final muted = Hp.muted(context);
    final faint = Hp.faint(context);
    Widget card(Widget child, {Color? bg, Color? border, EdgeInsets padding = const EdgeInsets.all(20), CrossAxisAlignment align = CrossAxisAlignment.start}) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: padding,
          decoration: BoxDecoration(color: bg ?? Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: border ?? Hp.line(context).withValues(alpha: 0.8), width: 0.8)),
          child: Column(crossAxisAlignment: align, children: [child]),
        );
    Text label(String t) => Text(t.toUpperCase(), style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: faint));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (ready)
        card(
          Column(children: [
            const Text('Your order is ready', style: TextStyle(fontSize: 18, height: 1.55, fontWeight: FontWeight.w700, color: Hp.ok)),
            const SizedBox(height: 4),
            Text('Tell the shop your pickup code at the counter.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.43, color: muted)),
          ]),
          bg: Hp.ok.withValues(alpha: 0.05),
          border: Hp.ok.withValues(alpha: 0.3),
          align: CrossAxisAlignment.center,
        ),
      if (cur == 1 && o.pickupPrepMinutes != null)
        card(
          Text.rich(TextSpan(style: const TextStyle(fontSize: 14, height: 1.43), children: [
            const TextSpan(text: 'Usually ready in about '),
            TextSpan(text: '${o.pickupPrepMinutes} min', style: const TextStyle(fontWeight: FontWeight.w600)),
            const TextSpan(text: " after the shop accepts. We'll message you the moment it is."),
          ])),
          padding: const EdgeInsets.all(16),
        ),
      if (showPass)
        card(
          Column(children: [
            label('Your pickup code'),
            const SizedBox(height: 8),
            Text(o.pickupCode!, style: const TextStyle(fontFamily: 'monospace', fontSize: 48, height: 1, fontWeight: FontWeight.w700, letterSpacing: 19)),
            const SizedBox(height: 8),
            Text('Tell this code to the shop when you collect.', style: TextStyle(fontSize: 13, height: 1.33, color: muted)),
            const SizedBox(height: 8),
            Text.rich(TextSpan(style: const TextStyle(fontSize: 14, height: 1.43), children: [const TextSpan(text: 'Order '), TextSpan(text: o.number, style: const TextStyle(fontWeight: FontWeight.w600))])),
          ]),
          align: CrossAxisAlignment.center,
        ),
      card(
        Column(children: [
          for (var i = 0; i < _stages.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _stages.length - 1 ? 0 : 16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: () {
                final done = i < cur || cur == 3;
                final active = i == cur && cur != 3;
                return <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: done
                        ? const Icon(Icons.check_circle_outline_rounded, size: 20, color: Hp.ok)
                        : Icon(active ? Icons.circle : Icons.circle_outlined, size: 20, color: active ? Hp.accent : Hp.lineStrong(context)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_stages[i].$1, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, color: !done && !active ? faint : null)),
                      if (active) Padding(padding: const EdgeInsets.only(top: 2), child: Text(_stages[i].$2, style: TextStyle(fontSize: 13, height: 1.33, color: muted))),
                    ]),
                  ),
                ];
              }()),
            ),
        ]),
      ),
      card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label('Pick up from'),
          const SizedBox(height: 8),
          Text(o.pickupShopName ?? o.shopName, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
          if ((o.pickupAddress ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.location_on_outlined, size: 16, color: muted)),
                const SizedBox(width: 8),
                Expanded(child: Text(o.pickupAddress!, style: TextStyle(fontSize: 14, height: 1.43, color: muted))),
              ]),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _directions, icon: const Icon(Icons.navigation_outlined, size: 16), label: const Text('Directions')),
            if (o.pickupPhone != null) OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${o.pickupPhone}')), icon: const Icon(Icons.phone_outlined, size: 16), label: const Text('Call shop')),
          ]),
        ]),
      ),
      card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label('Your order'),
          const SizedBox(height: 8),
          for (final l in o.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Text.rich(TextSpan(style: const TextStyle(fontSize: 14, height: 1.43), children: [TextSpan(text: '${l.quantity}× ${l.name}'), if (l.variation != null) TextSpan(text: ' (${l.variation})', style: TextStyle(color: faint))]))),
                const SizedBox(width: 12),
                Text('₹${l.lineTotal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, height: 1.43)),
              ]),
            ),
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Hp.line(context), width: 0.8))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
              Text('₹${o.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(o.amountDue > 0 ? 'Pay ₹${o.amountDue.toStringAsFixed(2)} at the shop when you collect.' : (o.paymentMethod == 'cod' ? 'Pay at the shop' : 'Paid online'), style: TextStyle(fontSize: 13, height: 1.33, fontWeight: o.amountDue > 0 ? FontWeight.w600 : FontWeight.w500, color: o.amountDue > 0 ? Hp.warn : faint)),
        ]),
        padding: const EdgeInsets.all(20),
      ),
    ]);
  }
}

/// Where the customer's money is, in the website's three steps: refund started, sent to the bank, in the account.
class _RefundCard extends StatelessWidget {
  const _RefundCard({required this.info, required this.orderId});
  final RefundInfo info;
  final String orderId;

  @override
  Widget build(BuildContext context) {
    final bad = info.needsAttention;
    final sent = info.state == 'sent' || info.state == 'completed';
    final c = bad ? Hp.bad : sent ? Hp.ok : Hp.muted(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: bad ? Hp.bad.withValues(alpha: 0.05) : Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: bad ? Hp.bad.withValues(alpha: 0.2) : Hp.line(context).withValues(alpha: 0.8), width: 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: bad ? Hp.bad.withValues(alpha: 0.1) : sent ? Hp.ok.withValues(alpha: 0.1) : Hp.surface2(context), shape: BoxShape.circle), child: Icon(bad ? Icons.warning_amber_rounded : sent ? Icons.check_rounded : Icons.replay_rounded, size: 20, color: c)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(info.headline, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, color: bad ? Hp.bad : null)),
              const SizedBox(height: 4),
              Text(info.summary, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        for (var i = 0; i < info.steps.length; i++)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Column(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: info.steps[i].state == 'done' ? Hp.ok : null,
                    border: info.steps[i].state == 'done' ? null : Border.all(color: info.steps[i].state == 'current' ? Hp.accent : Hp.line(context), width: 0.8),
                  ),
                  child: info.steps[i].state == 'done'
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : info.steps[i].state == 'current'
                          ? const Icon(Icons.schedule_rounded, size: 14, color: Hp.accent)
                          : Center(child: Text('${i + 1}', style: TextStyle(fontSize: 13, color: Hp.faint(context)))),
                ),
                if (i < info.steps.length - 1) Expanded(child: Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 4), color: info.steps[i].state == 'done' ? Hp.ok : Hp.line(context))),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(info.steps[i].label, style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: info.steps[i].state == 'todo' ? Hp.faint(context) : null)),
                    Text(info.steps[i].detail, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
                    if (info.steps[i].at != null) Text(DateFormat('d MMM, h:mm a').format(info.steps[i].at!), style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context))),
                  ]),
                ),
              ),
            ]),
          ),
        if (info.kept != null) Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(12)), child: Text(info.kept!, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context)))),
        if (info.arn != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('Bank reference (ARN): ${info.arn}. Your bank can use this to find the credit.', style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context)))),
        if (bad || sent)
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IssueScreen(orderId: orderId, orderNumber: ''))),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            child: Text(bad ? 'Ask us about this refund' : "Haven't received it? Tell us"),
          ),
      ]),
    );
  }
}

/// Puts the same dishes back in that shop's cart at today's prices and opens the cart. Dishes no longer available are
/// left out and said so. Shared by the order page and the Orders list.
Future<void> reorderOrder(BuildContext context, String orderId) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final r = await Api.reorder(orderId);
    if (r.shopHandle == null) throw ApiException('That shop is not available.');
    final menu = await Api.shop(r.shopHandle!);
    if (!menu.shop.canOrder) {
      throw ApiException(!menu.shop.open ? (menu.shop.closedReason ?? '${menu.shop.name} is closed right now.') : '${menu.shop.name} does not deliver to you.');
    }
    // Only this shop's cart is rebuilt; carts from other shops are left alone.
    Cart.instance.clearShop(menu.shop.id);
    var added = 0;
    var skipped = 0;
    for (final l in r.lines) {
      final idx = menu.items.indexWhere((i) => i.id == l['itemId']);
      if (idx < 0 || !menu.items[idx].available) {
        skipped += 1;
        continue;
      }
      final item = menu.items[idx];
      final wanted = ((l['optionIds'] as List?) ?? const []).map((e) => '$e').toSet();
      final chosen = [for (final g in item.groups) for (final o in g.options) if (wanted.contains(o.id)) o];
      // A required choice the shop has since changed cannot be guessed: that line is left for the customer to redo.
      final needs = item.groups.where((g) => g.required).any((g) => !g.options.any((o) => wanted.contains(o.id)));
      if (needs) {
        skipped += 1;
        continue;
      }
      Cart.instance.add(menu.shop, item, chosen: chosen, quantity: (l['quantity'] as num?)?.toInt() ?? 1);
      added += 1;
    }
    if (added == 0) throw ApiException('None of these dishes are available right now.');
    if (skipped > 0) {
      messenger.showSnackBar(SnackBar(content: Text('$skipped item${skipped == 1 ? ' is' : 's are'} no longer available and were left out.')));
    }
    navigator.popUntil((r) => r.isFirst);
    openCart();
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
