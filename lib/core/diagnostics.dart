import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';

/// Keeps a crash from being silent: anything the framework or a stray async call throws is logged on the server, and a
/// widget that fails to build shows a calm panel instead of the red error screen. There is no third-party service behind
/// this; the server writes each report to its own log, which is enough to learn that something broke and where.
class Diagnostics {
  static int _sent = 0;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static String? _version;

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      _report('flutter', details.exceptionAsString(), details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _report('async', '$error', stack);
      // Handled: the app keeps running rather than being torn down.
      return true;
    };
    ErrorWidget.builder = (details) => _FailedWidget(details: details);
  }

  static Future<void> _report(String kind, String message, StackTrace? stack) async {
    // A render loop can throw every frame; keep the log readable and the network quiet.
    final now = DateTime.now();
    if (_sent >= 8 || now.difference(_last) < const Duration(seconds: 5)) return;
    _sent += 1;
    _last = now;
    try {
      _version ??= (await PackageInfo.fromPlatform()).version;
      await http
          .post(
            Uri.parse('${AppConfig.siteUrl}/api/customer/diagnostics'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'kind': kind,
              'message': message.length > 600 ? message.substring(0, 600) : message,
              'stack': (stack?.toString() ?? '').split('\n').take(12).join('\n'),
              'version': _version,
              'platform': defaultTargetPlatform.name,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }
}

class _FailedWidget extends StatelessWidget {
  const _FailedWidget({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    // In a debug build the real error is more useful than a polite message.
    if (kDebugMode) return ErrorWidget(details.exception);
    return Container(
      color: const Color(0xFFF7F5FC),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Text('Something went wrong here. Go back and try again.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF6B6485), fontWeight: FontWeight.w700)),
    );
  }
}
