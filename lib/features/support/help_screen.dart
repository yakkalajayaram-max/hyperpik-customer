import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api.dart';
import '../../core/orders_models.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import 'issue_screen.dart';

String _statusLabel(String s) => switch (s) {
      'open' => 'Open',
      'with_ai' => 'With our assistant',
      'awaiting_vendor' => 'With the shop',
      'awaiting_customer' => 'Waiting for you',
      'escalated' => 'With Hyperpik',
      'resolved' => 'Resolved',
      _ => s,
    };

BadgeTone _statusTone(String s) => switch (s) {
      'resolved' => BadgeTone.ok,
      'awaiting_customer' => BadgeTone.warn,
      'escalated' => BadgeTone.bad,
      _ => BadgeTone.accent,
    };

/// Help & support inside the app: raise a ticket about an order, and read and answer the tickets already raised.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  List<SupportTicket>? _tickets;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await Api.supportTickets();
      if (mounted) {
        setState(() {
          _tickets = t;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Which order is it about? The recent ones, then the same "what went wrong" page as from an order.
  Future<void> _raise() async {
    final orders = await showModalBottomSheet<OrderSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PickOrderSheet(),
    );
    if (orders == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IssueScreen(orderId: orders.id, orderNumber: orders.number)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (Api.user == null) {
      return loginPromptPage(context, icon: Icons.help_outline_rounded, title: 'Log in to get help', body: 'Raise an issue with an order and follow what we are doing about it.', onSignedIn: () {
        if (mounted) setState(() {});
        _load();
      });
    }
    final tickets = _tickets;
    return SitePage(
      onRefresh: _load,
      bottom: 110,
      children: [
        const PageHeading(label: "We're here", title: 'Help & support', gap: 8),
        Padding(padding: const EdgeInsets.only(bottom: 24), child: Text("Tell us what went wrong and we'll sort it out, or put it straight in front of whoever can.", style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context)))),
        Padding(padding: const EdgeInsets.only(bottom: 32), child: Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: _raise, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Raise a ticket')))),
        if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 14, color: Hp.bad))
        else if (tickets == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (tickets.isEmpty)
          Container(width: double.infinity, padding: const EdgeInsets.all(32), decoration: cardDecoration(context), child: Text('Nothing raised yet. If something\'s wrong with an order, tap "Raise a ticket" above.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Hp.faint(context))))
        else ...[
          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Your issues', style: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700, letterSpacing: -0.4))),
          for (final t in tickets)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TicketScreen(ticketId: t.id)));
                  _load();
                },
                child: Ink(
                  padding: const EdgeInsets.all(16),
                  decoration: cardDecoration(context),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(t.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      HpBadge(_statusLabel(t.status), tone: _statusTone(t.status)),
                    ]),
                    const SizedBox(height: 4),
                    Text([if (t.orderNumber != null) 'Order ${t.orderNumber}', if (t.shopName != null) t.shopName!, DateFormat('d MMM yyyy').format(t.createdAt)].join(' · '), style: TextStyle(fontSize: 13, height: 1.33, color: Hp.faint(context))),
                  ]),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// The recent orders, to say which one the problem is about.
class _PickOrderSheet extends StatefulWidget {
  const _PickOrderSheet();

  @override
  State<_PickOrderSheet> createState() => _PickOrderSheetState();
}

class _PickOrderSheetState extends State<_PickOrderSheet> {
  List<OrderSummary>? _orders;

  @override
  void initState() {
    super.initState();
    Api.orders().then((o) {
      if (mounted) setState(() => _orders = o.take(15).toList());
    }).catchError((_) {
      if (mounted) setState(() => _orders = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Container(
        decoration: BoxDecoration(color: Hp.surface(context), borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), border: Border.all(color: Hp.line(context), width: 0.8)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Hp.line(context), width: 0.8))),
              child: Row(children: [
                const Expanded(child: Text('Which order is it about?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, size: 18, color: Hp.muted(context))),
              ]),
            ),
            if (orders == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (orders.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Text('You have no orders to report on yet.', style: TextStyle(fontSize: 14, color: Hp.muted(context))))
            else
              Flexible(
                child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                  for (final o in orders)
                    InkWell(
                      onTap: () => Navigator.pop(context, o),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Hp.line(context), width: 0.8))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(o.shopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              Text('${o.number} · ₹${o.total.toStringAsFixed(0)} · ${DateFormat('d MMM').format(o.createdAt)}', style: TextStyle(fontSize: 13, color: Hp.faint(context))),
                            ]),
                          ),
                          Icon(Icons.chevron_right_rounded, size: 16, color: Hp.faint(context)),
                        ]),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// One ticket and its conversation, with a box to write back once Hyperpik's team has it.
class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  SupportThread? _thread;
  String? _error;
  final _text = TextEditingController();
  bool _sending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await Api.supportTicket(widget.ticketId);
      if (mounted) {
        setState(() {
          _thread = t;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && _thread == null) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await Api.replyToTicket(widget.ticketId, text);
      _text.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _thread;
    return SitePage(
      onRefresh: _load,
      bottom: 110,
      children: [
        if (_error != null)
          Text(_error!, style: const TextStyle(fontSize: 14, color: Hp.bad))
        else if (t == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else ...[
          PageHeading(label: [if (t.orderNumber != null) 'Order ${t.orderNumber}', if (t.shopName != null) t.shopName!].join(' · ').isEmpty ? 'Your issue' : [if (t.orderNumber != null) 'Order ${t.orderNumber}', if (t.shopName != null) t.shopName!].join(' · '), title: t.summary, gap: 12),
          Padding(padding: const EdgeInsets.only(bottom: 20), child: Row(children: [HpBadge(_statusLabel(t.status), tone: _statusTone(t.status)), const SizedBox(width: 8), Text(DateFormat('d MMM yyyy, h:mm a').format(t.createdAt), style: TextStyle(fontSize: 13, color: Hp.faint(context)))])),
          if ((t.detail ?? '').isNotEmpty) Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16), decoration: cardDecoration(context), child: Text(t.detail!, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context)))),
          if ((t.resolution ?? '').isNotEmpty)
            Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Hp.ok.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.ok.withValues(alpha: 0.3), width: 0.8)), child: Text(t.resolution!, style: const TextStyle(fontSize: 14, height: 1.43))),
          for (final m in t.messages) _Bubble(message: m, shopName: t.shopName),
          const SizedBox(height: 8),
          if (t.canReply)
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4, maxLength: 1000, style: const TextStyle(fontSize: 14), decoration: InputDecoration(counterText: '', hintText: 'Write to Hyperpik', hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)))),
              const SizedBox(width: 8),
              FilledButton(onPressed: _sending ? null : _send, child: Text(_sending ? '…' : 'Send')),
            ])
          else if (t.status != 'resolved')
            Text("You'll be able to write here once Hyperpik's team has your ticket. We'll tell you.", style: TextStyle(fontSize: 13, height: 1.4, color: Hp.faint(context))),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.shopName});
  final SupportMessage message;
  final String? shopName;

  @override
  Widget build(BuildContext context) {
    final m = message;
    if (m.from == 'system' || m.kind == 'system') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Center(child: Text(m.body ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.4, color: Hp.faint(context)))));
    }
    final mine = m.from == 'customer';
    final who = switch (m.from) { 'ai' => 'Assistant', 'vendor' => shopName ?? 'The shop', 'admin' => 'Hyperpik', _ => '' };
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: mine ? Hp.tint(context) : Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: mine ? Hp.accent.withValues(alpha: 0.4) : Hp.line(context), width: 0.8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine && who.isNotEmpty) Text(who, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Hp.accentHi)),
          if (m.imageUrl != null) Padding(padding: const EdgeInsets.only(top: 4), child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(m.imageUrl!, height: 160, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
          if ((m.body ?? '').isNotEmpty) Text(m.body!, style: const TextStyle(fontSize: 14, height: 1.4)),
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(DateFormat('d MMM, h:mm a').format(m.at), style: TextStyle(fontSize: 11, color: Hp.faint(context)))),
        ]),
      ),
    );
  }
}
