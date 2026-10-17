import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/media.dart';
import '../../core/nav.dart';
import '../../core/orders_models.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'order_detail_screen.dart';

String statusLabel(String s) => switch (s) {
      'placed' => 'Waiting for the shop',
      'accepted' => 'Accepted',
      'processing' => 'Being prepared',
      'ready_for_pickup' => 'Ready, rider on the way',
      'out_for_delivery' => 'On the way',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      _ => s,
    };

Color statusColor(String s) => switch (s) {
      'delivered' => Hp.ok,
      'cancelled' => Hp.bad,
      _ => Hp.accent,
    };

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<OrderSummary>? _orders;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (Api.user == null) return;
    try {
      final o = await Api.orders();
      if (mounted) {
        setState(() {
          _orders = o;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The website sends a signed-out visitor to its login page.
    if (Api.user == null) return loginPromptPage(context, icon: Icons.receipt_long_outlined, title: 'Log in to see your orders', body: 'Your orders, live tracking and refunds are here once you log in.', onSignedIn: () {
      if (mounted) setState(() {});
      _load();
    });
    final orders = _orders;
    return SitePage(
      onRefresh: _load,
      onAuthChanged: _load,
      bottom: 110,
      children: [
        const PageHeading(label: 'History', title: 'My orders'),
        if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(children: [Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Try again'))]))
        else if (orders == null)
          const Column(children: [_OrderSkeleton(), _OrderSkeleton(), _OrderSkeleton()])
        else if (orders.isEmpty)
          EmptyCard(
            icon: Icons.receipt_long_outlined,
            title: 'No orders yet',
            body: 'When you place an order, it will show up here with live tracking.',
            actionLabel: 'Start shopping',
            onAction: () => shellTab.value = tabHome,
          )
        else
          for (final o in orders) _OrderCard(order: o, onBack: _load),
      ],
    );
  }
}

/// The website's order row labels.
String _rowLabel(OrderSummary o) {
  if (o.status == 'placed' && const {'pending', 'failed', 'created'}.contains(o.paymentStatus)) return o.paymentStatus == 'failed' ? 'Payment failed' : 'Payment incomplete';
  return switch (o.status) {
    'placed' => 'Order placed',
    'accepted' => 'Confirmed',
    'processing' => 'Preparing',
    'ready_for_pickup' => 'Ready for pickup',
    'out_for_delivery' => 'On the way',
    'delivered' => 'Delivered',
    'cancelled' => 'Cancelled',
    _ => o.status,
  };
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onBack});
  final OrderSummary order;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tone = order.status == 'delivered' ? BadgeTone.ok : (order.status == 'cancelled' ? BadgeTone.bad : BadgeTone.accent);
    final incomplete = order.status == 'placed' && const {'pending', 'failed', 'created'}.contains(order.paymentStatus);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: order.id)));
          onBack();
        },
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(context),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: ColoredBox(
                  color: Hp.surface2(context),
                  child: CachedNetworkImage(imageUrl: order.shopImageUrl ?? Media.cover('food', order.id), fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(order.shopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600))),
                  const SizedBox(width: 12),
                  Text(DateFormat('d/M/yyyy').format(order.createdAt), style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context))),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text('${order.number} · ₹${order.total.toStringAsFixed(0)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context)))),
                  const SizedBox(width: 8),
                  HpBadge(_rowLabel(order), tone: incomplete ? BadgeTone.warn : tone),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _OrderSkeleton extends StatelessWidget {
  const _OrderSkeleton();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(context),
          child: const Row(children: [
            Skeleton(height: 56, width: 56, radius: 12),
            SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(height: 16, width: 150), SizedBox(height: 12), Skeleton(height: 22, width: 160, radius: 999)])),
          ]),
        ),
      );
}
