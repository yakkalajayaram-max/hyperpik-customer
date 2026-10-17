import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/orders_models.dart';
import '../../core/theme.dart';
import '../orders/order_detail_screen.dart';

/// The website's bell panel: a card that hangs under the header, with the latest notifications and "Mark all read".
Future<void> showNotificationsPanel(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close notifications',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, __) => const _NotificationsPanel(),
    transitionBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  );
}

String _relative(DateTime at) {
  final secs = DateTime.now().difference(at).inSeconds;
  if (secs < 60) return 'just now';
  if (secs < 3600) return '${secs ~/ 60}m ago';
  if (secs < 86400) return '${secs ~/ 3600}h ago';
  return '${secs ~/ 86400}d ago';
}

class _NotificationsPanel extends StatefulWidget {
  const _NotificationsPanel();

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  List<AppNotification>? _items;
  int _unread = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.notifications();
      if (mounted) {
        setState(() {
          _items = r.items;
          _unread = r.unread;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _markAll() async {
    setState(() {
      _items = [for (final n in _items ?? const <AppNotification>[]) AppNotification(id: n.id, title: n.title, body: n.body, href: n.href, read: true, at: n.at)];
      _unread = 0;
    });
    try {
      await Api.markNotificationsRead();
    } catch (_) {}
  }

  void _open(AppNotification n) {
    final m = RegExp(r'^/orders/([^/?#]+)').firstMatch(n.href ?? '');
    Navigator.of(context).pop();
    if (m != null) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: m.group(1)!)));
    }
    if (!n.read) Api.markNotificationsRead().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final media = MediaQuery.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, media.padding.top + 64, 12, 0),
        child: Material(
          color: Hp.surface(context),
          elevation: 12,
          shadowColor: Colors.black,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Hp.line(context)), borderRadius: BorderRadius.circular(16)),
            constraints: BoxConstraints(maxHeight: media.size.height * 0.6 + 50),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Hp.line(context)))),
                child: Row(children: [
                  const Expanded(child: Text('Notifications', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
                  if (_unread > 0)
                    InkWell(
                      onTap: _markAll,
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_rounded, size: 14, color: Hp.accent),
                        SizedBox(width: 4),
                        Text('Mark all read', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: Hp.accent)),
                      ]),
                    ),
                ]),
              ),
              Flexible(
                child: _error != null
                    ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Hp.faint(context))))
                    : items == null
                        ? const Padding(padding: EdgeInsets.all(32), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                        : items.isEmpty
                            ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32), child: Center(child: Text('Nothing yet.', style: TextStyle(fontSize: 14, color: Hp.faint(context)))))
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: items.length,
                                itemBuilder: (_, i) {
                                  final n = items[i];
                                  return InkWell(
                                    onTap: () => _open(n),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: n.read ? null : Hp.tint(context).withValues(alpha: 0.4),
                                        border: i == items.length - 1 ? null : Border(bottom: BorderSide(color: Hp.line(context))),
                                      ),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          if (!n.read) Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 8), decoration: const BoxDecoration(color: Hp.accent, shape: BoxShape.circle)),
                                          Expanded(child: Text(n.title, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600))),
                                        ]),
                                        if (n.body != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(n.body!, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context)))),
                                        Padding(padding: const EdgeInsets.only(top: 2), child: Text(_relative(n.at), style: TextStyle(fontSize: 12, height: 1.45, color: Hp.faint(context)))),
                                      ]),
                                    ),
                                  );
                                },
                              ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
