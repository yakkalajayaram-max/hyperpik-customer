import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/api.dart';
import '../../core/cart_dock.dart';
import '../../core/map_style.dart';
import '../../core/orders_models.dart';
import '../../core/place.dart';
import '../../core/site_chrome.dart';
import '../../core/theme.dart';

/// The customer's saved addresses. With [pick] set it is a chooser and returns the address that was tapped.
class AddressesScreen extends StatefulWidget {
  const AddressesScreen({super.key, this.pick = false});
  final bool pick;

  @override
  State<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends State<AddressesScreen> {
  List<Address>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.addresses();
      if (mounted) setState(() => _list = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddAddressScreen(firstAddress: (_list ?? const []).isEmpty)));
    if (added == true) _load();
  }

  Future<void> _remove(Address a) async {
    try {
      await Api.deleteAddress(a.id);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  bool _all = false;

  @override
  Widget build(BuildContext context) {
    if (Api.user == null && !widget.pick) {
      return loginPromptPage(
        context,
        icon: Icons.location_on_outlined,
        title: 'Log in to see your addresses',
        body: 'Save where you want your orders delivered, and checkout is a single tap.',
        onSignedIn: () {
          if (mounted) setState(() {});
          _load();
        },
      );
    }
    final list = _list;
    final shown = list == null ? const <Address>[] : (_all ? list : list.take(5).toList());
    return SitePage(
      onRefresh: _load,
      bottom: 110,
      children: [
        PageHeading(label: 'Delivery', title: widget.pick ? 'Deliver to' : 'Your addresses', gap: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add a new address')),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_error!, textAlign: TextAlign.center),
          )
        else if (list == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final a in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.pick ? () => Navigator.pop(context, a) : null,
                child: Ink(
                  padding: const EdgeInsets.all(16),
                  decoration: cardDecoration(context),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(a.label, style: const TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w600)),
                                if (a.isDefault) const HpBadge('Default'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(a.fullAddress, style: TextStyle(fontSize: 14, height: 1.43, color: Hp.muted(context))),
                        AwayNote(a, fontSize: 13),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (widget.pick)
                        Icon(Icons.chevron_right_rounded, size: 16, color: Hp.faint(context))
                      else
                        InkWell(
                          onTap: () => _remove(a),
                          child: const Text(
                            'Remove',
                            style: TextStyle(fontSize: 14, height: 1.43, fontWeight: FontWeight.w500, color: Hp.bad),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (list.length > 5)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _all = !_all),
                icon: Icon(_all ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 16),
                label: Text(_all ? 'Show fewer' : 'Show all ${list.length} addresses (${list.length - 5} more)'),
              ),
            ),
          if (list.isEmpty) const EmptyCard(icon: Icons.location_on_outlined, title: 'No addresses yet', body: 'Add one so checkout is a single tap next time.'),
        ],
      ],
    );
  }
}

/// Pick the delivery spot on a map, search for it, or use the current location; then add the flat and a label.
class AddAddressScreen extends StatefulWidget {
  const AddAddressScreen({super.key, this.firstAddress = false});

  /// The first address is the default: there is nothing else for checkout to pick.
  final bool firstAddress;

  @override
  State<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends State<AddAddressScreen> with HidesCartDock {
  GoogleMapController? _map;
  final _house = TextEditingController();
  final _landmark = TextEditingController();
  final _building = TextEditingController();
  final _search = TextEditingController();
  Timer? _reverseDebounce;
  Timer? _searchDebounce;

  late LatLng _centre = LatLng(Place.instance.lat, Place.instance.lng);
  PlaceHit? _here;
  List<PlaceHit> _results = [];
  String? _searchNote;
  String _label = 'Home';
  bool _busy = false;
  bool _resolving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!Place.instance.isCurrent) _locate(silent: true);
    _resolve();
  }

  @override
  void dispose() {
    _reverseDebounce?.cancel();
    _searchDebounce?.cancel();
    _map?.dispose();
    for (final c in [_house, _building, _landmark, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _locate({bool silent = false}) async {
    final p = Place.instance;
    final ok = await p.useCurrent();
    if (!mounted) return;
    if (!ok) {
      if (!silent && p.problem != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(p.problem!)));
      return;
    }
    _go(LatLng(p.lat, p.lng));
  }

  void _go(LatLng to, {double zoom = 17}) {
    setState(() => _centre = to);
    _map?.animateCamera(CameraUpdate.newLatLngZoom(to, zoom));
    _resolve();
  }

  /// Names the spot under the pin once the map has stopped moving.
  void _resolve() {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() => _resolving = true);
      try {
        final hit = await Api.reverse(_centre.latitude, _centre.longitude);
        if (mounted) setState(() => _here = hit);
      } catch (_) {
        // The pin still works without a name; the customer can type the street.
      } finally {
        if (mounted) setState(() => _resolving = false);
      }
    });
  }

  void _onSearch(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 3) {
      setState(() {
        _results = [];
        _searchNote = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Api.searchPlaces(q.trim(), lat: _centre.latitude, lng: _centre.longitude);
        if (!mounted || _search.text.trim() != q.trim()) return;
        setState(() {
          _results = r;
          _searchNote = r.isEmpty ? 'No places match "${q.trim()}". Try a nearby landmark or move the map.' : null;
        });
      } catch (e) {
        if (mounted) setState(() => _searchNote = 'Search is unavailable right now. You can still move the map to your door.');
      }
    });
  }

  Future<void> _save() async {
    if (_house.text.trim().isEmpty) {
      setState(() => _error = 'Add your house or flat number so the rider can find you.');
      return;
    }
    final street = _here?.full ?? _here?.primary ?? 'Pinned location';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.addAddress(
        label: _label,
        type: _label == 'Work'
            ? 'work'
            : _label == 'Other'
            ? 'other'
            : 'home',
        houseNo: [_house.text.trim(), _building.text.trim()].where((e) => e.isNotEmpty).join(', '),
        street: street,
        landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
        pincode: _here?.pincode,
        city: _here?.city,
        lat: _centre.latitude,
        lng: _centre.longitude,
        isDefault: widget.firstAddress,
      );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = Hp.text(context);
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      hintStyle: TextStyle(fontSize: 16, color: Hp.faint(context)),
    );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Hp.page(context),
      body: Stack(
        children: [
          Column(
            children: [
              // ---- the website's top bar: a back arrow and the title ---------------------------------------------------------
              Container(
                padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 8, 8, 8),
                decoration: BoxDecoration(
                  color: Hp.surface(context),
                  border: Border(bottom: BorderSide(color: Hp.line(context))),
                ),
                child: Row(
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(context),
                      child: SizedBox(width: 44, height: 44, child: Icon(Icons.arrow_back_rounded, size: 20, color: hp)),
                    ),
                    const SizedBox(width: 8),
                    const Text('Add delivery address', style: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // ---- the map, with a pin that stays in the middle while the map moves under it ---------------------------------
                    Positioned.fill(
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(target: _centre, zoom: 16.5),
                        onMapCreated: (c) => _map = c,
                        // The pin stays in the middle; what is under it is where the address is. Named once the map stops.
                        onCameraMove: (pos) => _centre = pos.target,
                        onCameraIdle: _resolve,
                        style: Hp.isDark(context) ? kDarkMapStyle : null,
                        zoomControlsEnabled: false,
                        myLocationButtonEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                      ),
                    ),
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.location_on_rounded, size: 44, color: Hp.accent),
                      ),
                    ),

                    // ---- locate me -------------------------------------------------------------------------------------------------
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Hp.surface(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Hp.line(context)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () => _map?.animateCamera(CameraUpdate.zoomIn()),
                                  child: const SizedBox(width: 40, height: 40, child: Icon(Icons.add_rounded, size: 20)),
                                ),
                                Container(height: 1, width: 40, color: Hp.line(context)),
                                InkWell(
                                  onTap: () => _map?.animateCamera(CameraUpdate.zoomOut()),
                                  child: const SizedBox(width: 40, height: 40, child: Icon(Icons.remove_rounded, size: 20)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () => _locate(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Hp.surface(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Hp.line(context)),
                              ),
                              child: const Icon(Icons.my_location_rounded, size: 20, color: Hp.accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ---- the details sheet -----------------------------------------------------------------------------------------
              Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
                padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                decoration: BoxDecoration(
                  color: Hp.surface(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: Hp.line(context))),
                  boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 32, offset: Offset(0, -12))],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.location_on_outlined, size: 20, color: Hp.accent),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DELIVERING TO THIS SPOT',
                                  style: TextStyle(fontSize: 12, height: 1.45, fontWeight: FontWeight.w600, letterSpacing: 0.55, color: Hp.faint(context)),
                                ),
                                Text(
                                  _here == null ? (_resolving ? 'Finding where you are…' : 'Finding where you are…') : [_here!.primary, if (_here!.secondary.isNotEmpty) _here!.secondary].join(', '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, height: 1.375, fontWeight: FontWeight.w600, color: _here == null ? Hp.faint(context) : null),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(controller: _house, style: const TextStyle(fontSize: 16), decoration: field('House / flat no. *')),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(controller: _building, style: const TextStyle(fontSize: 16), decoration: field('Building / apartment')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(controller: _landmark, style: const TextStyle(fontSize: 16), decoration: field('Landmark (optional)')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final k in const [('Home', Icons.home_outlined), ('Work', Icons.work_outline_rounded), ('Other', Icons.pin_drop_outlined)]) ...[
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() => _label = k.$1),
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _label == k.$1 ? Hp.tint(context) : null,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _label == k.$1 ? Hp.accent : Hp.line(context)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(k.$2, size: 16, color: _label == k.$1 ? Hp.accentHi : Hp.muted(context)),
                                      const SizedBox(width: 6),
                                      Text(
                                        k.$1,
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _label == k.$1 ? Hp.accentHi : Hp.muted(context)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (k.$1 != 'Other') const SizedBox(width: 8),
                          ],
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(fontSize: 13, height: 1.33, fontWeight: FontWeight.w500, color: Hp.bad),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          onPressed: _busy ? null : _save,
                          child: Text(_busy ? 'Saving…' : 'Save and continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // ---- search: on top of the whole screen, so the suggestions are never cut off by the map or the details sheet ---------------------------------------------------------------------------------------------------
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 61 + 12,
            child: Column(
              children: [
                Material(
                  color: Hp.surface(context),
                  elevation: 3,
                  borderRadius: BorderRadius.circular(16),
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search area, street or landmark',
                      hintStyle: TextStyle(fontSize: 14, color: Hp.faint(context)),
                      prefixIcon: Icon(Icons.search_rounded, size: 16, color: Hp.faint(context)),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      isDense: true,
                      contentPadding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                    ),
                  ),
                ),
                if (_results.isEmpty && _searchNote != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Hp.surface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Hp.line(context)),
                    ),
                    child: Text(_searchNote!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                if (_results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Hp.surface(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Hp.line(context)),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final r in _results)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined, size: 18, color: Hp.accent),
                            title: Text(
                              r.primary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(r.secondary, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              setState(() {
                                _results = [];
                                _search.text = r.primary;
                              });
                              _go(LatLng(r.lat, r.lng));
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
