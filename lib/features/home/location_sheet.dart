import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/orders_models.dart';
import '../../core/place.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';
import '../account/addresses_screen.dart';
import '../account/sign_in_screen.dart';

/// Where should we deliver? A full screen, as in the design: search, "use current location", the places chosen before,
/// then "Confirm Location".
Future<void> showLocationSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, __) => const _LocationPanel(),
    transitionBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  );
}

/// The website's "Deliver to" menu: the saved addresses (the chosen one ticked), "Use my current location" and "Add a new
/// address". One more row, "Search for an area", opens the full search for someone with no saved address or no GPS.
class _LocationPanel extends StatefulWidget {
  const _LocationPanel();

  @override
  State<_LocationPanel> createState() => _LocationPanelState();
}

class _LocationPanelState extends State<_LocationPanel> {
  List<Address> _addresses = [];
  bool _locating = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    if (Api.user != null) {
      Api.addresses().then((a) {
        if (mounted) setState(() => _addresses = a);
      }).catchError((_) {});
    }
  }

  bool _selected(Address a) {
    final p = Place.instance;
    return p.isCurrent && a.hasLocation && (p.lat - a.lat!).abs() < 0.00005 && (p.lng - a.lng!).abs() < 0.00005;
  }

  void _choose(Address a) {
    Place.instance.setChosen(lat: a.lat!, lng: a.lng!, title: a.label, subtitle: a.fullAddress, saved: true);
    Navigator.of(context).pop();
  }

  Future<void> _useCurrent() async {
    setState(() {
      _locating = true;
      _note = null;
    });
    final ok = await Place.instance.useCurrent();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _locating = false;
        _note = Place.instance.problem ?? "Couldn't get your location. Allow location access, or pick an address.";
      });
    }
  }

  Future<void> _add() async {
    final nav = Navigator.of(context);
    nav.pop();
    if (Api.user == null) {
      await nav.push(MaterialPageRoute<void>(builder: (_) => const SignInScreen(popOnSuccess: true)));
      if (Api.user == null) return;
    }
    await nav.push(MaterialPageRoute<bool>(builder: (_) => AddAddressScreen(firstAddress: _addresses.isEmpty)));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final muted = Hp.muted(context);
    Widget action(IconData icon, String label, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 16, color: Hp.accent),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.accent))),
            ]),
          ),
        );
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, media.padding.top + 8 + 48 + 4, 16, 0),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: (media.size.width * 0.92).clamp(0, 352).toDouble()),
          child: Material(
            color: Hp.surface(context),
            elevation: 8,
            shadowColor: Colors.black,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Hp.line(context), width: 0.8), borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Hp.line(context).withValues(alpha: 0.7), width: 0.8))),
                  child: Text('Show stores that deliver to', style: TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w600, color: muted)),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 288),
                  child: _addresses.isEmpty
                      ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Text('No saved addresses yet.', style: TextStyle(fontSize: 13, height: 1.33, color: muted)))
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          children: [
                            for (final a in _addresses)
                              InkWell(
                                onTap: a.hasLocation ? () => _choose(a) : null,
                                child: Opacity(
                                  opacity: a.hasLocation ? 1 : 0.6,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        margin: const EdgeInsets.only(top: 2),
                                        decoration: BoxDecoration(shape: BoxShape.circle, color: _selected(a) ? Hp.accent : null, border: Border.all(color: _selected(a) ? Hp.accent : Hp.lineStrong(context), width: 0.8)),
                                        child: _selected(a) ? const Icon(Icons.check_rounded, size: 12, color: Colors.white) : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Row(children: [
                                            Text(a.label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                                            if (a.isDefault) ...[
                                              const SizedBox(width: 8),
                                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Hp.tint(context), borderRadius: BorderRadius.circular(999)), child: const Text('Default', style: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w600, color: Hp.accent))),
                                            ],
                                          ]),
                                          Padding(padding: const EdgeInsets.only(top: 2), child: Text(a.fullAddress, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.33, color: muted))),
                                          AwayNote(a, fontSize: 12),
                                          if (!a.hasLocation) Padding(padding: const EdgeInsets.only(top: 2), child: Text('No map pin: edit it to use here', style: TextStyle(fontSize: 12, height: 1.45, color: Hp.faint(context)))),
                                        ]),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                Container(
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: Hp.line(context).withValues(alpha: 0.7), width: 0.8))),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    action(Icons.my_location_rounded, _locating ? 'Finding you…' : 'Use my current location', _locating ? null : _useCurrent),
                    action(Icons.search_rounded, 'Search for an area', () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.push(MaterialPageRoute<void>(builder: (_) => const _LocationScreen()));
                    }),
                    action(Icons.add_rounded, 'Add a new address', _add),
                  ]),
                ),
                if (_note != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Hp.line(context).withValues(alpha: 0.7), width: 0.8))),
                    child: Text(_note!, style: const TextStyle(fontSize: 13, height: 1.33, color: Hp.bad)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pending {
  _Pending(this.lat, this.lng, this.title, this.subtitle);
  final double lat;
  final double lng;
  final String title;
  final String subtitle;
}

class _LocationScreen extends StatefulWidget {
  const _LocationScreen();

  @override
  State<_LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<_LocationScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<PlaceHit> _results = [];
  List<Address> _saved = [];
  bool _searching = false;
  bool _locating = false;
  String? _note;
  _Pending? _pending;

  @override
  void initState() {
    super.initState();
    if (Api.user != null) {
      Api.addresses().then((a) {
        if (mounted) setState(() => _saved = a.where((x) => x.hasLocation).toList());
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.length < 3) {
      setState(() {
        _results = [];
        _note = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Api.searchPlaces(q, lat: Place.instance.lat, lng: Place.instance.lng);
        if (!mounted || _query.text.trim() != q) return;
        setState(() {
          _results = r;
          _searching = false;
          _note = r.isEmpty ? 'No places match "$q". Try a nearby area or landmark.' : null;
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _searching = false;
            _note = 'Search is not available right now. You can still use your current location.';
          });
        }
      }
    });
  }

  void _select(double lat, double lng, String title, String subtitle) {
    HapticFeedback.selectionClick();
    setState(() => _pending = _Pending(lat, lng, title, subtitle));
  }

  bool _isPending(double lat, double lng) => _pending != null && (_pending!.lat - lat).abs() < 0.00001 && (_pending!.lng - lng).abs() < 0.00001;

  void _confirm() {
    final p = _pending;
    if (p == null) return;
    Place.instance.setChosen(lat: p.lat, lng: p.lng, title: p.title, subtitle: p.subtitle);
    Navigator.of(context).pop();
  }

  Future<void> _useCurrent() async {
    setState(() {
      _locating = true;
      _note = null;
    });
    final ok = await Place.instance.useCurrent();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _locating = false;
        _note = Place.instance.problem ?? 'Could not find your location.';
      });
    }
  }

  Widget _row({required IconData icon, required String title, required String subtitle, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: selected ? Hp.accent.withValues(alpha: 0.14) : Colors.transparent),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: Hp.accent.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Icon(icon, color: Hp.accentHi, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              if (subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Hp.muted(context)))),
            ]),
          ),
          if (selected) const Icon(Icons.check_circle_rounded, color: Hp.accentHi, size: 22),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = Hp.muted(context);
    final place = Place.instance;
    Widget heading(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 8), child: Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)));

    return Scaffold(
      appBar: AppBar(title: const Text('Select your location')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: _pending == null ? null : _confirm,
            child: const Text('Confirm Location'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          TextField(
            controller: _query,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search area, street or pincode',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searching
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)))
                  : (_query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _query.clear();
                            _onChanged('');
                          },
                        )),
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _locating ? null : _useCurrent,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context))),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: Hp.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: _locating ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2.4)) : const Icon(Icons.my_location_rounded, color: Hp.accentHi, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Use current location', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('Detect your current location', style: TextStyle(fontSize: 12.5, color: muted)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: muted),
              ]),
            ),
          ),
          if (_note != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_note!, style: const TextStyle(color: Hp.bad, fontWeight: FontWeight.w700))),
          if (_results.isNotEmpty) ...[
            heading('Search results'),
            for (final r in _results)
              _row(icon: Icons.location_on_outlined, title: r.primary, subtitle: r.secondary, selected: _isPending(r.lat, r.lng), onTap: () => _select(r.lat, r.lng, r.primary, r.secondary)),
          ] else ...[
            if (_saved.isNotEmpty) ...[
              heading('Saved addresses'),
              for (final a in _saved)
                _row(
                  icon: a.type == 'work' ? Icons.work_outline_rounded : (a.type == 'other' ? Icons.location_on_outlined : Icons.home_outlined),
                  title: a.label,
                  subtitle: a.fullAddress,
                  selected: _isPending(a.lat!, a.lng!),
                  onTap: () => _select(a.lat!, a.lng!, a.label, a.fullAddress),
                ),
            ],
            if (place.recents.isNotEmpty) ...[
              heading('Recent locations'),
              for (final r in place.recents)
                _row(icon: Icons.history_rounded, title: r.title, subtitle: r.subtitle, selected: _isPending(r.lat, r.lng), onTap: () => _select(r.lat, r.lng, r.title, r.subtitle)),
            ],
          ],
          if (place.isCurrent)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: () async {
                  await Place.instance.useDefault();
                  if (mounted) Navigator.of(context).pop();
                },
                child: const Text('Browse without a location'),
              ),
            ),
        ],
      ),
    );
  }
}
