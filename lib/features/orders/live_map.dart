import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/map_style.dart';
import '../../core/theme.dart';
import 'map_icons.dart';

/// Where the order is: the shop, the customer's door and, once a rider has it, the rider, on Google Maps. The view fits
/// all the points. As the website's map: a 288 px rounded card, zoom buttons, and a legend line.
class LiveMap extends StatefulWidget {
  const LiveMap({super.key, this.shop, this.drop, this.rider, required this.shopName, this.shopImageUrl, this.route = const []});
  final (double, double)? shop;
  final (double, double)? drop;
  final (double, double)? rider;
  final String shopName;
  final String? shopImageUrl;
  final List<(double, double)> route;

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  GoogleMapController? _map;
  BitmapDescriptor? _shopPin;
  BitmapDescriptor? _homePin;
  BitmapDescriptor? _bikePin;

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final shop = await shopPin(widget.shopImageUrl);
    final home = await iconPin('home', Icons.home_rounded, const Color(0xFF16A34A));
    final bike = await iconPin('bike', Icons.two_wheeler_rounded, Hp.accent);
    if (mounted) setState(() { _shopPin = shop; _homePin = home; _bikePin = bike; });
  }

  LatLng _l((double, double) p) => LatLng(p.$1, p.$2);

  List<LatLng> get _points => [if (widget.shop != null) _l(widget.shop!), if (widget.drop != null) _l(widget.drop!), if (widget.rider != null) _l(widget.rider!)];

  /// Frames every point, or centres on the one there is.
  Future<void> _fit() async {
    final c = _map;
    final points = _points;
    if (c == null || points.isEmpty) return;
    try {
      if (points.length == 1) {
        await c.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
        return;
      }
      final south = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
      final north = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
      final west = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
      final east = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
      await c.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: LatLng(south, west), northeast: LatLng(north, east)), 56));
    } catch (_) {
      // The map was torn down while the camera was moving.
    }
  }

  @override
  void didUpdateWidget(LiveMap old) {
    super.didUpdateWidget(old);
    // The rider moved or appeared: keep everyone in view.
    if (old.rider != widget.rider || old.shop != widget.shop || old.drop != widget.drop || old.route.length != widget.route.length) _fit();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final drop = widget.drop;
    final rider = widget.rider;
    final points = _points;
    if (points.isEmpty) return const SizedBox.shrink();
    const centre = Offset(0.5, 0.5);

    return Container(
      height: 240,
      decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(20), border: Border.all(color: Hp.line(context), width: 0.8)),
      clipBehavior: Clip.antiAlias,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: points.first, zoom: 15),
        onMapCreated: (c) {
          _map = c;
          // After the first layout, or the bounds are fitted to a map that has no size yet.
          Future<void>.delayed(const Duration(milliseconds: 350), _fit);
        },
        style: Hp.isDark(context) ? kDarkMapStyle : null,
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: false,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        // The map is inside a scrolling page: it takes the touch when a finger is on it, so it can be panned.
        gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
        polylines: {
          if (widget.route.length >= 2) Polyline(polylineId: const PolylineId('route'), points: [for (final p in widget.route) _l(p)], width: 5, color: Hp.accent, jointType: JointType.round, startCap: Cap.roundCap, endCap: Cap.roundCap),
        },
        markers: {
          if (shop != null && _shopPin != null) Marker(markerId: const MarkerId('shop'), position: _l(shop), icon: _shopPin!, anchor: centre),
          if (drop != null && _homePin != null) Marker(markerId: const MarkerId('drop'), position: _l(drop), icon: _homePin!, anchor: centre),
          if (rider != null && _bikePin != null) Marker(markerId: const MarkerId('rider'), position: _l(rider), icon: _bikePin!, anchor: centre, zIndexInt: 2),
        },
      ),
    );
  }
}
