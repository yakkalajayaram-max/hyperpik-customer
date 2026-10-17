import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/map_style.dart';
import '../../core/theme.dart';

/// Where the order is: the shop, the customer's door and, once a rider has it, the rider, on Google Maps. The view fits
/// all the points. As the website's map: a 288 px rounded card, zoom buttons, and a legend line.
class LiveMap extends StatefulWidget {
  const LiveMap({super.key, this.shop, this.drop, this.rider, required this.shopName});
  final (double, double)? shop;
  final (double, double)? drop;
  final (double, double)? rider;
  final String shopName;

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  GoogleMapController? _map;

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
    if (old.rider != widget.rider || old.shop != widget.shop || old.drop != widget.drop) _fit();
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

    Widget legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, height: 1.33, color: Hp.muted(context))),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 288,
        decoration: BoxDecoration(color: Hp.surface2(context), borderRadius: BorderRadius.circular(24), border: Border.all(color: Hp.line(context), width: 0.8)),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          GoogleMap(
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
            markers: {
              if (shop != null) Marker(markerId: const MarkerId('shop'), position: _l(shop), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange), infoWindow: InfoWindow(title: widget.shopName)),
              if (drop != null) Marker(markerId: const MarkerId('drop'), position: _l(drop), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen), infoWindow: const InfoWindow(title: 'You')),
              if (rider != null) Marker(markerId: const MarkerId('rider'), position: _l(rider), icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet), infoWindow: const InfoWindow(title: 'Rider'), zIndexInt: 2),
            },
            polylines: {
              if (shop != null && drop != null)
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: [_l(shop), _l(drop)],
                  width: 4,
                  color: Hp.accent.withValues(alpha: 0.7),
                  patterns: [PatternItem.dash(18), PatternItem.gap(12)],
                ),
            },
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              decoration: BoxDecoration(color: Hp.surface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: Hp.line(context), width: 0.8)),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                InkWell(onTap: () => _map?.animateCamera(CameraUpdate.zoomIn()), child: const SizedBox(width: 40, height: 40, child: Icon(Icons.add_rounded, size: 20))),
                Container(height: 1, width: 40, color: Hp.line(context)),
                InkWell(onTap: () => _map?.animateCamera(CameraUpdate.zoomOut()), child: const SizedBox(width: 40, height: 40, child: Icon(Icons.remove_rounded, size: 20))),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 4, children: [
        if (shop != null) legend(const Color(0xFFF97316), widget.shopName),
        if (drop != null) legend(Hp.ok, 'You'),
        if (rider != null) legend(Hp.accent, 'Rider'),
      ]),
    ]);
  }
}
