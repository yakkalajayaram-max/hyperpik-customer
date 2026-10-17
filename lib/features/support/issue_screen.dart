import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/cart_dock.dart';
import '../../core/orders_models.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';

/// Report a problem with an order, in the words that fit what was sold. The choices come from the same catalogue the website
/// uses, and the report is routed the same way: to the shop, or straight to Hyperpik when it is serious.
class IssueScreen extends StatefulWidget {
  const IssueScreen({super.key, required this.orderId, required this.orderNumber});
  final String orderId;
  final String orderNumber;

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _IssueScreenState extends State<IssueScreen> with HidesCartDock {
  IssueOptions? _options;
  String? _error;
  IssueOption? _picked;
  String? _item;
  final _detail = TextEditingController();
  bool _busy = false;
  String? _doneMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await Api.issueOptions(widget.orderId);
      if (mounted) setState(() => _options = o);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final p = _picked;
    if (p == null) return;
    if (p.needsItem && _item == null) {
      setState(() => _error = p.itemPrompt ?? 'Choose the item.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final msg = await Api.reportIssue(widget.orderId, key: p.key, itemLabel: _item, detail: _detail.text.trim());
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _doneMessage = msg);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_doneMessage != null) {
      return SitePage(
        bottom: 40,
        children: [
          EmptyCard(icon: Icons.check_rounded, title: 'We are on it', body: _doneMessage!, actionLabel: 'Back to my order', onAction: () => Navigator.pop(context)),
        ],
      );
    }

    final o = _options;
    final muted = Hp.muted(context);
    return SitePage(
      bottom: 40,
      children: [
        PageHeading(label: 'Help', title: widget.orderNumber.isEmpty ? 'Report an issue' : 'Help with ${widget.orderNumber}', gap: 24),
        if (_error != null && o == null)
          Text(_error!, style: const TextStyle(fontSize: 14, color: Hp.bad))
        else if (o == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else ...[
          const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('What went wrong?', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
          for (final g in o.groups.where((g) => g.options.isNotEmpty)) ...[
            Padding(padding: const EdgeInsets.only(bottom: 8, top: 4), child: Text(g.label.toUpperCase(), style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: muted))),
            for (final opt in g.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    _picked = opt;
                    _item = null;
                    _error = null;
                  }),
                  child: Ink(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _picked?.key == opt.key ? Hp.tint(context) : Hp.surface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _picked?.key == opt.key ? Hp.accent : Hp.line(context), width: 0.8),
                    ),
                    child: Row(children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: _picked?.key == opt.key ? Colors.white : null, border: Border.all(color: _picked?.key == opt.key ? Hp.accent : Hp.lineStrong(context), width: _picked?.key == opt.key ? 4.5 : 1.5)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(opt.label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (_picked != null) ...[
            if (_picked!.needsItem && o.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_picked!.itemPrompt ?? 'Which item?', style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final i in o.items)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _item = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: _item == i ? Hp.tint(context) : null, borderRadius: BorderRadius.circular(999), border: Border.all(color: _item == i ? Hp.accent : Hp.line(context), width: 0.8)),
                      child: Text(i, style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: _item == i ? Hp.accentHi : muted)),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 24),
            const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Tell us what happened', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
            TextField(controller: _detail, maxLines: 4, minLines: 4, maxLength: 1000, style: const TextStyle(fontSize: 14), decoration: InputDecoration(hintText: 'A few details help us fix it faster', hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10))),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.bad))),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, height: 44, child: FilledButton(onPressed: _busy ? null : _send, child: Text(_busy ? 'Sending…' : 'Send'))),
          ],
        ],
      ],
    );
  }
}
