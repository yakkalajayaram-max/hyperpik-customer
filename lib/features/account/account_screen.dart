import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api.dart';
import '../support/help_screen.dart';
import '../support/in_app_page.dart';
import '../../core/favourites.dart';
import '../../core/nav.dart';
import '../../core/push.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import '../../core/theme_controller.dart';
import 'become_seller_screen.dart';
import 'favourites_screen.dart';
import '../reservations/reservations_screens.dart';
import 'notifications_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  StreamSubscription<AuthState>? _sub;
  Map<String, dynamic>? _profile;
  int _unread = 0;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _sub = Api.db.auth.onAuthStateChange.listen((_) {
      _load();
      Favourites.instance.load();
    });
    _load();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version} (${p.buildNumber})');
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (Api.user == null) {
      if (mounted) setState(() => _profile = null);
      return;
    }
    try {
      final p = await Api.profile();
      final n = await Api.notifications();
      if (mounted) {
        setState(() {
          _profile = p;
          _unread = n.unread;
        });
      }
    } catch (_) {}
  }

  bool _editing = false;
  bool _saving = false;
  final _nameC = TextEditingController();
  final _phoneC = TextEditingController();

  void _startEdit() {
    _nameC.text = '${_profile?['name'] ?? ''}';
    _phoneC.text = '${_profile?['phone'] ?? ''}'.replaceFirst(RegExp(r'^\+?91'), '');
    setState(() => _editing = true);
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await Api.saveProfile(name: _nameC.text.trim().isEmpty ? null : _nameC.text.trim(), phone: _phoneC.text.trim().isEmpty ? null : _phoneC.text.trim());
      await _load();
      if (mounted) setState(() => _editing = false);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete your account?', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your addresses, favourites and saved details are removed and you will not be able to sign in with this number again. Past orders stay on record for the shops and for accounting, without your name.'),
          const SizedBox(height: 14),
          TextField(controller: c, decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my account')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Hp.bad), onPressed: () => Navigator.pop(ctx, c.text.trim() == 'DELETE'), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteAccount();
      await Push.unregister();
      await Api.signOut();
      shellTab.value = tabHome;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Api.user;
    if (user == null) {
      return loginPromptPage(context, icon: Icons.person_outline_rounded, title: 'Log in to your account', body: 'Your profile, saved addresses and favourites are here once you log in.', onSignedIn: () {
        if (mounted) setState(() {});
        _load();
      });
    }
    final name = '${_profile?['name'] ?? ''}'.trim();
    final phone = '${_profile?['phone'] ?? user.phone ?? ''}';
    final email = '${_profile?['email'] ?? user.email ?? ''}'.trim();
    final muted = Hp.muted(context);

    Widget row(String k, String v) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(fontSize: 14, height: 1.43, color: muted)),
          const SizedBox(width: 16),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500))),
        ]);

    Widget field(String label, TextEditingController c, {TextInputType? type, String? prefix}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            keyboardType: type,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(isDense: true, prefixText: prefix, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
          ),
        ]);

    Widget linkRow(IconData icon, String label, VoidCallback onTap, {Widget? trailing, bool last = false}) => InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Hp.line(context), width: 0.8))),
            child: Row(children: [
              Icon(icon, size: 16, color: Hp.accent),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500))),
              trailing ?? Icon(Icons.chevron_right_rounded, size: 16, color: Hp.faint(context)),
            ]),
          ),
        );

    Widget linkCard(List<Widget> rows) => Container(margin: const EdgeInsets.only(bottom: 24), clipBehavior: Clip.antiAlias, decoration: cardDecoration(context), child: Column(children: rows));
    void open(String title, String path) => openSitePage(context, title, path);

    return SitePage(
      onRefresh: _load,
      onAuthChanged: _load,
      unread: _unread,
      bottom: 116,
      children: [
        const PageHeading(label: 'Profile', title: 'Your account'),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: cardDecoration(context),
          child: _editing
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  field('Name', _nameC),
                  const SizedBox(height: 12),
                  field('Mobile number', _phoneC, type: TextInputType.phone, prefix: '+91  '),
                  const SizedBox(height: 16),
                  Row(children: [
                    FilledButton(onPressed: _saving ? null : _saveProfile, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8)), child: Text(_saving ? 'Saving…' : 'Save')),
                    const SizedBox(width: 12),
                    TextButton(onPressed: () => setState(() => _editing = false), style: TextButton.styleFrom(foregroundColor: muted, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)), child: const Text('Cancel')),
                  ]),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  row('Phone', phone.isEmpty ? '—' : '+91 ${phone.replaceAll(RegExp(r'^\+?91'), '')}'),
                  const SizedBox(height: 12),
                  row('Name', name.isEmpty ? 'Not set' : name),
                  const SizedBox(height: 12),
                  row('Email', email.isEmpty ? 'Not set' : email),
                  const SizedBox(height: 12),
                  InkWell(onTap: _startEdit, child: const Text('Edit profile', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.accent))),
                ]),
        ),
        linkCard([
          linkRow(Icons.receipt_long_outlined, 'My orders', () => shellTab.value = tabOrders),
          linkRow(Icons.favorite_border_rounded, 'Favourites', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavouritesScreen()))),
          linkRow(Icons.event_seat_outlined, 'Table bookings', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyReservationsScreen()))),
          linkRow(Icons.location_on_outlined, 'Saved addresses', () => shellTab.value = tabAddresses),
          linkRow(
            Icons.notifications_none_rounded,
            'Notifications',
            () async {
              await showNotificationsPanel(context);
              _load();
            },
            trailing: _unread > 0 ? HpBadge('$_unread') : null,
          ),
          linkRow(Icons.help_outline_rounded, 'Help & support', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen())), last: true),
        ]),
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Appearance', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: ThemeController.instance,
              builder: (context, _) => SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_rounded, size: 16)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined, size: 16)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined, size: 16)),
                  ],
                  selected: {ThemeController.instance.mode},
                  onSelectionChanged: (v) => ThemeController.instance.set(v.first),
                ),
              ),
            ),
          ]),
        ),
        InkWell(
          onTap: () async {
            await Push.unregister();
            await Api.signOut();
            shellTab.value = tabHome;
          },
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.logout_rounded, size: 16, color: Hp.bad),
            SizedBox(width: 8),
            Text('Log out', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.bad)),
          ]),
        ),
        const SizedBox(height: 32),
        linkCard([
          linkRow(Icons.storefront_outlined, 'Become a seller', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BecomeSellerScreen()))),
          linkRow(Icons.policy_outlined, 'Cancellation & refunds', () => open('Cancellation & refunds', '/refund-policy')),
          linkRow(Icons.shield_outlined, 'Privacy policy', () => open('Privacy policy', '/privacy')),
          linkRow(Icons.description_outlined, 'Terms & conditions', () => open('Terms & conditions', '/terms')),
          linkRow(Icons.local_shipping_outlined, 'Shipping & delivery', () => open('Shipping & delivery', '/shipping-policy')),
          linkRow(Icons.info_outline_rounded, 'About us', () => open('About us', '/about')),
          linkRow(Icons.mail_outline_rounded, 'Contact us', () => open('Contact us', '/contact'), last: true),
        ]),
        InkWell(
          onTap: _delete,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete_outline_rounded, size: 16, color: Hp.bad),
            SizedBox(width: 8),
            Text('Delete my account', style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.bad)),
          ]),
        ),
        if (_version.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 20), child: Text('Hyperpik $_version', style: TextStyle(fontSize: 13, color: Hp.faint(context)))),
      ],
    );
  }
}
