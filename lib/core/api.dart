import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'geo_cache.dart';
import 'models.dart';
import 'orders_models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Everything the app asks the website. Signed-in calls carry the Supabase access token, which the website
/// accepts as a Bearer header; browsing works without one.
class Api {
  Api._();

  static SupabaseClient get db => Supabase.instance.client;
  /// Dev preview only: a made-up signed-in customer, so every signed-in screen can be laid out in a browser.
  static const _previewUser = bool.fromEnvironment('PREVIEW_USER');
  static final _fakeUser = User(id: 'preview', appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '2026-01-01T00:00:00Z', phone: '919999999999');

  static User? get user {
    if (_previewUser) return _fakeUser;
    try {
      return db.auth.currentUser;
    } catch (_) {
      // Before the auth client exists (a unit test, the first frame) nobody is signed in.
      return null;
    }
  }

  static Map<String, String> _headers() {
    final token = db.auth.currentSession?.accessToken;
    return {'Accept': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// [signedIn] false leaves the sign-in off the request: for public map data, so the website's edge can keep one answer and
  /// hand it to everyone who asks the same thing.
  static Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query, bool signedIn = true]) async {
    final uri = Uri.parse('${AppConfig.siteUrl}$path').replace(queryParameters: query);
    final http.Response res;
    try {
      res = await http.get(uri, headers: signedIn ? _headers() : const {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ApiException('No connection. Check your internet and try again.');
    }
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw ApiException('${body['error'] ?? 'Something went wrong. Please try again.'}', status: res.statusCode);
    }
    return body;
  }

  static Future<HomeData> home({double? lat, double? lng, String? category, String? query}) async {
    final body = await _get('/api/customer/home', {
      if (lat != null && lng != null) 'lat': '$lat',
      if (lat != null && lng != null) 'lng': '$lng',
      if (category != null) 'category': category,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    });
    return HomeData.fromJson(body);
  }

  static Future<ShopMenu> shop(String handle, {double? lat, double? lng}) async {
    final body = await _get('/api/customer/shops/${Uri.encodeComponent(handle)}', {
      if (lat != null) 'lat': '$lat',
      if (lng != null) 'lng': '$lng',
    });
    return ShopMenu.fromJson(body);
  }

  static Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic> body = const {}]) async {
    final uri = Uri.parse('${AppConfig.siteUrl}$path');
    final http.Response res;
    try {
      res = await http
          .post(uri, headers: {..._headers(), 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      throw ApiException('No connection. Check your internet and try again.');
    }
    Map<String, dynamic> out = {};
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) out = decoded;
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw ApiException('${out['error'] ?? 'Something went wrong. Please try again.'}', status: res.statusCode);
    }
    return out;
  }

  static Future<void> _delete(String path) async {
    final res = await http.delete(Uri.parse('${AppConfig.siteUrl}$path'), headers: _headers()).timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) throw ApiException('Could not remove that.', status: res.statusCode);
  }

  // ---- addresses ---------------------------------------------------------------------------------------------

  static List<Address> _addresses(Map<String, dynamic> body) =>
      ((body['addresses'] as List?) ?? const []).map((a) => Address.fromJson(Map<String, dynamic>.from(a as Map))).toList();

  static Future<List<Address>> addresses() async => _addresses(await _get('/api/customer/addresses'));

  static Future<List<Address>> addAddress({
    required String label,
    required String type,
    required String houseNo,
    required String street,
    String? landmark,
    String? pincode,
    String? city,
    required double lat,
    required double lng,
    bool isDefault = false,
  }) async =>
      _addresses(await _post('/api/customer/addresses', {
        'label': label,
        'type': type,
        'houseNo': houseNo,
        'street': street,
        'landmark': landmark,
        'pincode': pincode,
        'city': city,
        'lat': lat,
        'lng': lng,
        'isDefault': isDefault,
      }));

  static Future<void> deleteAddress(String id) => _delete('/api/customer/addresses/$id');

  // ---- checkout ----------------------------------------------------------------------------------------------

  /// Makes the server's cart the same as the phone's, immediately before pricing it.
  static Future<void> syncCart(String shopId, List<Map<String, dynamic>> lines) =>
      _post('/api/customer/cart/sync', {'vendorId': shopId, 'lines': lines});

  static Future<Quote> quote({required String shopId, String? addressId, bool pickup = false, required String method, String? coupon}) async =>
      Quote.fromJson(await _post('/api/customer/checkout/quote', {
        'vendorId': shopId,
        if (addressId != null) 'addressId': addressId,
        'fulfilment': pickup ? 'pickup' : 'delivery',
        'paymentMethod': method,
        'couponCode': coupon,
      }));

  static Future<PlacedOrder> placeOrder({required String shopId, String? addressId, bool pickup = false, required String method, String? coupon, String? note, String? contactPhone}) async =>
      PlacedOrder.fromJson(await _post('/api/customer/checkout', {
        'vendorId': shopId,
        if (addressId != null) 'addressId': addressId,
        'fulfilment': pickup ? 'pickup' : 'delivery',
        'paymentMethod': method,
        'couponCode': coupon,
        'orderNote': note,
        if (contactPhone != null) 'contactPhone': contactPhone,
      }));

  static Future<void> confirmPayment({required String orderId, required String paymentId, required String signature}) =>
      _post('/api/customer/checkout/confirm', {'orderId': orderId, 'razorpayPaymentId': paymentId, 'razorpaySignature': signature});

  // ---- orders ------------------------------------------------------------------------------------------------

  static Future<List<OrderSummary>> orders() async {
    final body = await _get('/api/customer/orders');
    return ((body['orders'] as List?) ?? const []).map((o) => OrderSummary.fromJson(Map<String, dynamic>.from(o as Map))).toList();
  }

  static Future<OrderDetail> order(String id) async => OrderDetail.fromJson(await _get('/api/customer/orders/$id'));

  static Future<void> cancelOrder(String id, String reason) => _post('/api/customer/orders/$id/cancel', {'reason': reason});

  // ---- help & support ----------------------------------------------------------------------------------------

  static Future<List<SupportTicket>> supportTickets() async {
    final b = await _get('/api/customer/support/tickets');
    return ((b['tickets'] as List?) ?? const []).map((t) => SupportTicket.fromJson(Map<String, dynamic>.from(t as Map))).toList();
  }

  static Future<SupportThread> supportTicket(String id) async => SupportThread.fromJson(await _get('/api/customer/support/tickets/$id'));

  static Future<void> replyToTicket(String id, String text) => _post('/api/customer/support/tickets/$id', {'text': text});

  // ---- profile -----------------------------------------------------------------------------------------------

  static Future<Map<String, dynamic>> profile() => _get('/api/customer/profile');

  static Future<void> saveProfile({String? name, String? phone}) => _post('/api/customer/profile', {'name': name, 'phone': phone});

  // ---- extras ------------------------------------------------------------------------------------------------

  static Future<List<Shop>> favourites({double? lat, double? lng}) async {
    final b = await _get('/api/customer/favorites', {if (lat != null) 'lat': '$lat', if (lng != null) 'lng': '$lng'});
    return ((b['shops'] as List?) ?? const []).map((s) => Shop.fromJson(Map<String, dynamic>.from(s as Map))).toList();
  }

  static Future<bool> toggleFavourite(String shopId) async => (await _post('/api/customer/favorites', {'vendorId': shopId}))['favourite'] == true;

  // Address lookups are public map data and repeat constantly (the same street, the pin nudged a step), so they are
  // remembered here for a while and sent in rounded form so the website's edge can answer neighbours from one copy.
  static final _searches = TtlCache<List<PlaceHit>>(max: 60, ttl: const Duration(hours: 1));
  static final _reverses = TtlCache<PlaceHit>(max: 120, ttl: const Duration(hours: 24));

  static Future<List<PlaceHit>> searchPlaces(String q, {double? lat, double? lng}) async {
    final text = queryKey(q);
    // The position only steers which city a street name belongs to, so about a kilometre is exact enough.
    final la = lat == null || lng == null ? null : roundTo(lat, 2);
    final ln = lat == null || lng == null ? null : roundTo(lng, 2);
    final hits = await _searches.once('$text|$la,$ln', () async {
      final b = await _get('/api/customer/places', {'q': text, if (la != null) 'lat': '$la', if (ln != null) 'lng': '$ln'}, false);
      return ((b['places'] as List?) ?? const []).map((p) => PlaceHit.fromJson(Map<String, dynamic>.from(p as Map))).toList();
    }, keep: (v) => v.isNotEmpty);
    return hits ?? const [];
  }

  /// What is at a position. With [area], the street or neighbourhood rather than the nearest shop: what a header should
  /// say, since a shop name changes with every few metres of GPS drift.
  static Future<PlaceHit?> reverse(double lat, double lng, {bool area = false}) {
    // About 11 m for an exact pin, 110 m for a street or neighbourhood, which holds still.
    final places = area ? 3 : 4;
    final la = roundTo(lat, places).toStringAsFixed(places);
    final ln = roundTo(lng, places).toStringAsFixed(places);
    return _reverses.once('${area ? 'a' : 'p'}|$la,$ln', () async {
      final b = await _get('/api/customer/places', {'lat': la, 'lng': ln, if (area) 'area': '1'}, false);
      return b['place'] == null ? null : PlaceHit.fromJson(Map<String, dynamic>.from(b['place'] as Map));
    });
  }

  /// Delivered orders not yet rated, newest first: what the rating prompt asks about.
  static Future<List<({String id, String number, String shopName})>> ordersToReview() async {
    final body = await _get('/api/customer/orders/to-review');
    return [
      for (final o in ((body['orders'] as List?) ?? const []))
        (id: '${(o as Map)['id']}', number: '${o['number']}', shopName: '${o['shopName'] ?? 'the shop'}'),
    ];
  }

  static Future<void> review(String orderId, int rating, String comment) => _post('/api/customer/orders/$orderId/review', {'rating': rating, 'comment': comment});

  /// The shop and lines of a past order, to put back in the cart.
  static Future<({String? shopHandle, List<Map<String, dynamic>> lines})> reorder(String orderId) async {
    final b = await _get('/api/customer/orders/$orderId/reorder');
    return (shopHandle: b['shopHandle'] as String?, lines: ((b['lines'] as List?) ?? const []).map((l) => Map<String, dynamic>.from(l as Map)).toList());
  }

  static Future<List<OfferInfo>> offers({required String shopId, required num subtotal, required num delivery, required String method}) async {
    final b = await _get('/api/customer/offers', {'vendorId': shopId, 'subtotal': '$subtotal', 'delivery': '$delivery', 'method': method});
    return ((b['offers'] as List?) ?? const []).map((o) => OfferInfo.fromJson(Map<String, dynamic>.from(o as Map))).toList();
  }

  static Future<({int unread, List<AppNotification> items})> notifications() async {
    final b = await _get('/api/customer/notifications');
    return (
      unread: (b['unread'] as num?)?.toInt() ?? 0,
      items: ((b['items'] as List?) ?? const []).map((n) => AppNotification.fromJson(Map<String, dynamic>.from(n as Map))).toList(),
    );
  }

  static Future<void> markNotificationsRead() => _post('/api/customer/notifications');

  static Future<IssueOptions> issueOptions(String orderId) async => IssueOptions.fromJson(await _get('/api/customer/orders/$orderId/issue'));

  static Future<String> reportIssue(String orderId, {required String key, String? itemLabel, required String detail}) async {
    final b = await _post('/api/customer/orders/$orderId/issue', {'key': key, 'itemLabel': itemLabel, 'detail': detail});
    return '${b['message'] ?? 'Sent.'}';
  }

  static Future<void> deleteAccount() async {
    final req = http.Request('DELETE', Uri.parse('${AppConfig.siteUrl}/api/customer/account'))
      ..headers.addAll({..._headers(), 'Content-Type': 'application/json'})
      ..body = jsonEncode({'confirm': 'DELETE'});
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
    if (res.statusCode >= 400) {
      String msg = 'Could not delete your account.';
      try {
        msg = '${(jsonDecode(res.body) as Map)['error'] ?? msg}';
      } catch (_) {}
      throw ApiException(msg, status: res.statusCode);
    }
  }

  // ---- sign-in -----------------------------------------------------------------------------------------------

  static String _phone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final ten = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    return '${AppConfig.phoneCountryCode}$ten';
  }

  /// Sends the login code. WhatsApp by default, SMS when [sms] is set: the website's order. Supabase's send hook never learns
  /// which channel was asked for, so it is recorded on the site a moment before (the same side channel the website uses).
  static Future<void> sendPhoneOtp(String phone, {bool sms = false}) async {
    final full = _phone(phone);
    try {
      await http
          .post(Uri.parse('${AppConfig.siteUrl}/api/auth/otp-channel'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'phone': full, 'channel': sms ? 'sms' : 'whatsapp'}))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Best effort: without it the code still goes out on the default channel.
    }
    await db.auth.signInWithOtp(phone: full, channel: sms ? OtpChannel.sms : OtpChannel.whatsapp);
  }

  static Future<AuthResponse> verifyPhoneOtp(String phone, String code) =>
      db.auth.verifyOTP(phone: _phone(phone), token: code.trim(), type: OtpType.sms);

  /// A login code by email, for someone who signs in with an address rather than a number.
  static Future<void> sendEmailOtp(String email) => db.auth.signInWithOtp(email: email.trim());

  static Future<AuthResponse> verifyEmailOtp(String email, String code) => db.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email);

  /// Google. On a phone this is the native account chooser (no browser): Google returns an ID token and Supabase signs the
  /// customer in with it. When the web client id is not configured, or the native flow is unavailable, it falls back to the
  /// browser flow with the same web client the website uses.
  static Future<void> signInWithGoogle() async {
    if (AppConfig.googleWebClientId.isNotEmpty && !kIsWeb) {
      try {
        final google = GoogleSignIn.instance;
        await google.initialize(serverClientId: AppConfig.googleWebClientId);
        final account = await google.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) throw const AuthException('Google did not return a sign-in token. Please try again.');
        await db.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
        return;
      } on GoogleSignInException catch (e) {
        // The customer closing the chooser is not an error.
        if (e.code == GoogleSignInExceptionCode.canceled) return;
        // Anything else (not set up for this app build, no Play services): use the browser instead.
      }
    }
    await db.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: AppConfig.authRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  static Future<void> signOut() => db.auth.signOut();
}
