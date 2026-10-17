import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'orders_models.dart';

/// A place the customer chose before, offered again under "Recent locations".
class RecentPlace {
  RecentPlace({required this.lat, required this.lng, required this.title, this.subtitle = ''});
  final double lat;
  final double lng;
  final String title;
  final String subtitle;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'title': title, 'subtitle': subtitle};
  factory RecentPlace.fromJson(Map<String, dynamic> j) =>
      RecentPlace(lat: (j['lat'] as num).toDouble(), lng: (j['lng'] as num).toDouble(), title: '${j['title']}', subtitle: '${j['subtitle'] ?? ''}');
}

/// Where the customer is browsing from. It decides distances and which shops can deliver to them, so it is kept
/// between launches and starts from the city default until they share their location.
class Place extends ChangeNotifier {
  Place._();
  static final Place instance = Place._();

  double lat = AppConfig.defaultLat;
  double lng = AppConfig.defaultLng;
  String label = AppConfig.defaultPlace;

  /// A second line under the name when the place came from a search or a saved address ("Kothapet, Hyderabad").
  String subtitle = '';
  bool isCurrent = false;
  bool locating = false;

  /// True when the chosen place is one of the customer's saved addresses (picked by them or by [autoSelect]), as opposed
  /// to the phone's own position or a searched place.
  bool savedAddress = false;

  /// Said under "Deliver to" when a chosen saved address is not where the phone is: "You are 320 m away". Worked out
  /// from the phone's position each time, so it holds however the address was chosen and follows the phone as it moves.
  String? get awayNote {
    if (!savedAddress || deviceLat == null || deviceLng == null) return null;
    final d = Geolocator.distanceBetween(deviceLat!, deviceLng!, lat, lng);
    return d > atAddressMetres ? 'You are ${readableDistance(d)} away' : null;
  }

  /// Where the phone itself is, as last found. Separate from the chosen place: it is what "You are 320 m away" is
  /// measured from. Null until a position is known.
  double? deviceLat;
  double? deviceLng;

  /// "You are here" or "You are 320 m away" for a saved address; null when either position is unknown.
  String? distanceTo(Address a) {
    if (deviceLat == null || deviceLng == null || !a.hasLocation) return null;
    final d = Geolocator.distanceBetween(deviceLat!, deviceLng!, a.lat!, a.lng!);
    return d <= atAddressMetres ? 'You are here' : 'You are ${readableDistance(d)} away';
  }

  /// Bumped when the customer chooses somewhere themselves, so a lookup still running does not undo their choice.
  int _epoch = 0;
  bool _auto = false;

  /// Within this of a saved address, the phone is "at" it. Beyond it, the distance is shown.
  static const atAddressMetres = 50;

  /// Further than this from every saved address and the phone's own position is used instead.
  static const nearAddressMetres = 1000;

  /// "320 m" up close, "1.2 km" once metres stop meaning anything. Rounded before the unit is chosen, so 995 m reads
  /// "1.0 km" and never "1000 m".
  static String readableDistance(double metres) {
    final rounded = (metres / 10).round() * 10;
    return rounded < 1000 ? '$rounded m' : '${(metres / 1000).toStringAsFixed(1)} km';
  }
  String? problem;
  final List<RecentPlace> recents = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      lat = p.getDouble('place_lat') ?? lat;
      lng = p.getDouble('place_lng') ?? lng;
      label = p.getString('place_label') ?? label;
      subtitle = p.getString('place_subtitle') ?? '';
      final raw = p.getString('place_recents');
      if (raw != null) {
        recents
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => RecentPlace.fromJson(Map<String, dynamic>.from(e as Map))));
      }
      isCurrent = p.getBool('place_current') ?? false;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('place_lat', lat);
      await p.setDouble('place_lng', lng);
      await p.setString('place_label', label);
      await p.setString('place_subtitle', subtitle);
      await p.setString('place_recents', jsonEncode(recents.map((r) => r.toJson()).toList()));
      await p.setBool('place_current', isCurrent);
    } catch (_) {}
  }

  /// Asks for permission if needed, then uses the phone's position. Leaves the previous place alone on any failure.
  Future<bool> useCurrent() async {
    locating = true;
    problem = null;
    notifyListeners();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        problem = 'Turn on location in your phone settings.';
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        problem = 'Location permission was not given.';
        return false;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      _epoch++;
      deviceLat = pos.latitude;
      deviceLng = pos.longitude;
      await _applyFix(pos.latitude, pos.longitude);
      return true;
    } catch (_) {
      problem = 'Could not find your location. Try again.';
      return false;
    } finally {
      locating = false;
      notifyListeners();
    }
  }


  /// Makes this position the place, named by what is there. Naming is best effort: the position already works.
  Future<void> _applyFix(double la, double ln) async {
    // Opening the app at home again: the name from last time (kept on the phone) still fits, so no lookup at all.
    final sameSpot = isCurrent && !savedAddress && label.isNotEmpty && label != 'Current location' && Geolocator.distanceBetween(lat, lng, la, ln) < 100;
    if (sameSpot) {
      lat = la;
      lng = ln;
      await _save();
      notifyListeners();
      return;
    }
    lat = la;
    lng = ln;
    label = 'Current location';
    subtitle = '';
    isCurrent = true;
    savedAddress = false;
    await _save();
    notifyListeners();
    try {
      final hit = await Api.reverse(lat, lng, area: true).timeout(const Duration(seconds: 8));
      if (hit != null && hit.primary.isNotEmpty) {
        // OpenStreetMap often names the ward ("Ward 21 Kothapet"); the area name is what a person would say.
        final cleaned = hit.primary.replaceFirst(RegExp(r'^ward\s*(no\.?)?\s*\d+\s*', caseSensitive: false), '').trim();
        label = cleaned.isEmpty ? hit.primary : cleaned;
        subtitle = hit.secondary;
        _remember(lat, lng, label, subtitle);
        await _save();
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Picks where to deliver from where the phone is, as the website does when it opens:
  ///   - a saved address within [atAddressMetres]: that address;
  ///   - one within [nearAddressMetres] but further off: that address, with "You are 320 m away";
  ///   - none that close, or none saved (or not signed in): the phone's own position, named from the map.
  /// Needs location already allowed (the first launch asks); without it, the choice made last time stands.
  Future<void> autoSelect() async {
    if (_auto) return;
    _auto = true;
    final epoch = _epoch;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium)).timeout(const Duration(seconds: 15));

      deviceLat = pos.latitude;
      deviceLng = pos.longitude;
      notifyListeners();

      var saved = <Address>[];
      if (Api.user != null) {
        try {
          saved = (await Api.addresses()).where((a) => a.hasLocation).toList();
        } catch (_) {}
      }
      if (epoch != _epoch) return;

      Address? nearest;
      var best = double.infinity;
      for (final a in saved) {
        final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, a.lat!, a.lng!);
        if (d < best) {
          best = d;
          nearest = a;
        }
      }

      if (nearest != null && best < nearAddressMetres) {
        lat = nearest.lat!;
        lng = nearest.lng!;
        label = nearest.label;
        subtitle = nearest.fullAddress;
        isCurrent = true;
        problem = null;
        savedAddress = true;
        await _save();
        notifyListeners();
      } else {
        await _applyFix(pos.latitude, pos.longitude);
      }
    } catch (_) {
      // No fix in time: whatever was chosen before stays.
    } finally {
      _auto = false;
    }
  }

  void _remember(double lat, double lng, String title, String subtitle) {
    recents.removeWhere((r) => (r.lat - lat).abs() < 0.0005 && (r.lng - lng).abs() < 0.0005);
    recents.insert(0, RecentPlace(lat: lat, lng: lng, title: title, subtitle: subtitle));
    if (recents.length > 5) recents.removeRange(5, recents.length);
  }

  /// A place the customer picked from a search or from their saved addresses.
  void setChosen({required double lat, required double lng, required String title, String subtitle = '', bool saved = false}) {
    this.lat = lat;
    this.lng = lng;
    label = title;
    this.subtitle = subtitle;
    isCurrent = true;
    problem = null;
    savedAddress = saved;
    _epoch++;
    _remember(lat, lng, title, subtitle);
    _save();
    notifyListeners();
  }

  Future<void> useDefault() async {
    lat = AppConfig.defaultLat;
    lng = AppConfig.defaultLng;
    label = AppConfig.defaultPlace;
    subtitle = '';
    isCurrent = false;
    problem = null;
    savedAddress = false;
    _epoch++;
    await _save();
    notifyListeners();
  }
}
