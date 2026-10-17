import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or whatever the phone is set to (the default). The choice is kept between launches.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'theme_mode';

  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode = switch (p.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {}
  }

  Future<void> set(ThemeMode next) async {
    if (next == mode) return;
    mode = next;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, next.name);
    } catch (_) {}
  }
}
