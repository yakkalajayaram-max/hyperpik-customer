import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Small round map pins drawn in code: a bike for the rider, a home for the door, and the shop's own picture for the shop.
/// Cached, because the map asks for them every time the rider moves.
final Map<String, BitmapDescriptor> _cache = {};

const double _px = 112; // drawn large and shown small, so it stays sharp on dense screens

Future<BitmapDescriptor> _render(void Function(Canvas c, Size s) paint) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  paint(canvas, const Size(_px, _px));
  final img = await rec.endRecording().toImage(_px.toInt(), _px.toInt());
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  return BitmapDescriptor.bytes(Uint8List.fromList(bytes), width: 40, height: 40);
}

void _disc(Canvas c, Color fill) {
  const r = _px / 2;
  c.drawCircle(const Offset(r, r + 2), r - 4, Paint()..color = Colors.black.withValues(alpha: 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  c.drawCircle(const Offset(r, r), r - 6, Paint()..color = Colors.white);
  c.drawCircle(const Offset(r, r), r - 12, Paint()..color = fill);
}

void _glyph(Canvas c, IconData icon, Color color) {
  final tp = TextPainter(
    text: TextSpan(text: String.fromCharCode(icon.codePoint), style: TextStyle(fontSize: 56, fontFamily: icon.fontFamily, package: icon.fontPackage, color: color)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset((_px - tp.width) / 2, (_px - tp.height) / 2));
}

Future<BitmapDescriptor> iconPin(String key, IconData icon, Color fill) async {
  final hit = _cache[key];
  if (hit != null) return hit;
  return _cache[key] = await _render((c, s) {
    _disc(c, fill);
    _glyph(c, icon, Colors.white);
  });
}

/// The shop's own picture in a round pin; a shop icon when it has none or the picture cannot be loaded.
Future<BitmapDescriptor> shopPin(String? url) async {
  final key = 'shop:${url ?? ''}';
  final hit = _cache[key];
  if (hit != null) return hit;
  ui.Image? photo;
  if (url != null && url.isNotEmpty) {
    try {
      final done = Completer<ui.Image>();
      final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
      late ImageStreamListener l;
      l = ImageStreamListener((info, _) {
        if (!done.isCompleted) done.complete(info.image);
        stream.removeListener(l);
      }, onError: (e, _) {
        if (!done.isCompleted) done.completeError(e);
      });
      stream.addListener(l);
      photo = await done.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      photo = null;
    }
  }
  if (photo == null) return _cache[key] = await iconPin('shop-fallback', Icons.storefront_rounded, const Color(0xFFF97316));
  final p = photo;
  return _cache[key] = await _render((c, s) {
    const r = _px / 2;
    _disc(c, Colors.white);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: const Offset(r, r), radius: r - 12)));
    final side = p.width < p.height ? p.width.toDouble() : p.height.toDouble();
    final src = Rect.fromCenter(center: Offset(p.width / 2, p.height / 2), width: side, height: side);
    c.drawImageRect(p, src, Rect.fromCircle(center: const Offset(r, r), radius: r - 12), Paint()..filterQuality = FilterQuality.medium);
    c.restore();
  });
}
