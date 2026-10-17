import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/orders/order_detail_screen.dart';
import 'cart_dock.dart';
import 'config.dart';
import 'nav.dart';

/// Notifications while the app is closed: accepted, on the way, delivered, refund sent.
///
/// Firebase is only the delivery pipe. The phone's token is saved on the server against the signed-in customer, and
/// Hyperpik's own notifications are sent to it (lib/push/fcm.ts on the website). Everything here is best effort: a
/// phone without Google services, or a customer who declines notifications, simply gets no push and nothing else
/// changes.
class Push {
  Push._();

  static bool _started = false;
  static String? _token;

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  /// The channel the server addresses its pushes to (`channel_id: "orders"` in lib/push/fcm.ts). It has to exist on the
  /// phone, or Android 8+ files the notification under a generic, quiet default.
  static const _channel = AndroidNotificationChannel(
    'orders',
    'Order updates',
    description: 'Your order being accepted, on the way, delivered or refunded.',
    importance: Importance.high,
  );

  /// Called once at launch. Safe to call when Firebase is not available.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      await _initLocal();
      // The app is open: Android shows nothing by itself, so show it ourselves.
      FirebaseMessaging.onMessage.listen(_showForeground);
      // The app was in the background and the customer tapped the notification.
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _open(m.data['href'] as String?));
      // The app was closed and the notification started it.
      final first = await fm.getInitialMessage();
      if (first != null) {
        Future<void>.delayed(const Duration(milliseconds: 1200), () => _open(first.data['href'] as String?));
      }
      _token = await fm.getToken();
      fm.onTokenRefresh.listen((t) {
        _token = t;
        register();
      });
      Supabase.instance.client.auth.onAuthStateChange.listen((s) {
        if (s.session != null) register();
      });
      await register();
    } catch (_) {
      // No Play services, or Firebase not configured: the app works the same without push.
    }
  }

  static Future<void> _initLocal() async {
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
  }

  static Future<void> _showForeground(RemoteMessage m) async {
    final n = m.notification;
    if (n == null) return;
    await _local.show(
      id: m.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_channel.id, _channel.name, channelDescription: _channel.description, importance: Importance.high, priority: Priority.high),
      ),
      payload: m.data['href'] as String?,
    );
  }

  /// Takes the customer where a notification points: the order, or the Orders tab.
  static void _open(String? href) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final m = RegExp(r'^/orders/([0-9a-fA-F-]{8,})').firstMatch(href ?? '');
    nav.popUntil((r) => r.isFirst);
    if (m != null) {
      nav.push(MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: m.group(1)!)));
    } else {
      shellTab.value = tabOrders;
    }
  }

  /// Tells the server this phone belongs to the signed-in customer. A no-op when signed out or without a token.
  static Future<void> register() async {
    final token = _token;
    final session = Supabase.instance.client.auth.currentSession;
    if (token == null || session == null) return;
    try {
      await http
          .post(
            Uri.parse('${AppConfig.siteUrl}/api/customer/push/register'),
            headers: {'Authorization': 'Bearer ${session.accessToken}', 'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Forgets this phone for the account that is signing out, so the next person on it gets nothing meant for them.
  static Future<void> unregister() async {
    final token = _token;
    final session = Supabase.instance.client.auth.currentSession;
    if (token == null || session == null) return;
    try {
      final req = http.Request('DELETE', Uri.parse('${AppConfig.siteUrl}/api/customer/push/register'))
        ..headers.addAll({'Authorization': 'Bearer ${session.accessToken}', 'Content-Type': 'application/json'})
        ..body = jsonEncode({'token': token});
      await req.send().timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
