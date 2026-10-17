import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/theme.dart';

/// "How was your order from X?", asked the next time the customer opens the app after a delivery.
///
/// A bottom sheet, not a page: one tap on a star is enough, the comment is optional and it can be put off. "Not now"
/// hides it for this visit only, so it asks again next time; "Don't ask about this order" is the way out for good.
/// Asked at most once per app start, and never over a checkout (it is only called from the shell).
class ReviewPrompt {
  static bool _askedThisSession = false;
  static const _skippedKey = 'review.skipped';

  static Future<Set<String>> _skipped() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_skippedKey);
      if (raw == null) return {};
      return {for (final v in (jsonDecode(raw) as List)) '$v'};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _skip(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final all = (await _skipped()).toList()..add(id);
      await p.setString(_skippedKey, jsonEncode(all.length > 50 ? all.sublist(all.length - 50) : all));
    } catch (_) {}
  }

  /// Looks for an order to ask about and, if there is one, shows the sheet. Quiet on any failure: a prompt is a nicety.
  static Future<void> maybeAsk(BuildContext context) async {
    if (_askedThisSession || Api.user == null) return;
    try {
      final pending = await Api.ordersToReview();
      final skipped = await _skipped();
      final next = pending.where((o) => !skipped.contains(o.id)).toList();
      if (next.isEmpty || !context.mounted) return;
      _askedThisSession = true;
      final o = next.first;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Hp.surface(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => _Sheet(order: o, onNever: () => _skip(o.id)),
      );
    } catch (_) {}
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({required this.order, required this.onNever});
  final ({String id, String number, String shopName}) order;
  final Future<void> Function() onNever;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _thanks = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_stars < 1) {
      setState(() => _error = 'Tap a star first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.review(widget.order.id, _stars, _comment.text.trim());
      if (!mounted) return;
      setState(() {
        _thanks = true;
        _busy = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: _thanks
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Thank you! Your rating helps ${o.shopName} and other customers.', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            )
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ORDER ${o.number.replaceFirst('#', '')} WAS DELIVERED', style: TextStyle(fontSize: 13, height: 1.33, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: Hp.faint(context))),
              const SizedBox(height: 4),
              Text('How was your order from ${o.shopName}?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.5)),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: _busy ? null : () => setState(() => _stars = i),
                    iconSize: 32,
                    icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= _stars ? Hp.star : Hp.lineStrong(context)),
                  ),
              ]),
              if (_stars > 0)
                TextField(controller: _comment, maxLength: 300, maxLines: 2, decoration: const InputDecoration(hintText: 'Anything you would like the shop to know? (optional)')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: Hp.bad, fontWeight: FontWeight.w700))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: FilledButton(onPressed: _busy || _stars < 1 ? null : _send, child: Text(_busy ? 'Sending…' : 'Submit rating'))),
                const SizedBox(width: 10),
                TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Not now')),
              ]),
              Center(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await widget.onNever();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                  child: Text("Don't ask about this order", style: TextStyle(fontSize: 13, color: Hp.muted(context))),
                ),
              ),
            ]),
    );
  }
}
