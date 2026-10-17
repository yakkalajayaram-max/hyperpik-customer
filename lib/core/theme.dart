import 'package:flutter/material.dart';

/// Hyperpik's look, taken value for value from the website's design tokens (hyperpik-web/app/globals.css), so a screen in
/// the app and the same screen on the website's mobile view are the same colours, radii and type.
///
/// Dark, light or the phone's own setting (see ThemeController). Text is a little heavier and the quiet greys a little
/// lighter than the website's, because a phone screen is read at arm's length in all kinds of light.
class Hp {
  // ---- the website's dark tokens ------------------------------------------------------------------------------------
  static const bg = Color(0xFF0D0A17);
  static const surfaceDark = Color(0xFF161122);
  static const surface2Dark = Color(0xFF1F1930);
  static const lineDark = Color(0xFF2A2340);
  static const lineStrongDark = Color(0xFF3A3054);
  static const textDark = Color(0xFFF3EFFC);
  static const mutedDark = Color(0xFFBBB3D4);
  static const faintDark = Color(0xFF9189AC);

  static const accent = Color(0xFF8B5CF6);
  static const accentHi = Color(0xFFA78BFA);
  static const accentSoft = Color(0xFF2A1F52);
  static const accentDeep = Color(0xFF5B21E6);
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const bad = Color(0xFFF87171);
  static const star = Color(0xFFFBBF24);
  static const veg = Color(0xFF16A34A);
  static const nonVeg = Color(0xFFB91C1C);

  /// The accent's glow under a raised button (the website's --shadow-glow).
  static const glow = Color(0x598B5CF6);

  /// The header wash used where a screen has one.
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A1280), Color(0xFF5B21E6), Color(0xFF8B5CF6)],
  );

  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color surface(BuildContext c) => isDark(c) ? surfaceDark : Colors.white;
  static Color surface2(BuildContext c) => isDark(c) ? surface2Dark : const Color(0xFFF1EEF8);
  static Color line(BuildContext c) => isDark(c) ? lineDark : const Color(0xFFE8E4F0);
  static Color lineStrong(BuildContext c) => isDark(c) ? lineStrongDark : const Color(0xFFD4CDE3);
  static Color text(BuildContext c) => isDark(c) ? textDark : const Color(0xFF1A1228);
  static Color muted(BuildContext c) => isDark(c) ? mutedDark : const Color(0xFF5B5570);
  static Color faint(BuildContext c) => isDark(c) ? faintDark : const Color(0xFF7A7490);

  /// The page behind the cards.
  static Color page(BuildContext c) => isDark(c) ? bg : const Color(0xFFF6F5FB);

  /// The website's --accent-soft: the quiet purple behind an active control or an icon plate.
  static Color tint(BuildContext c) => isDark(c) ? accentSoft : const Color(0xFFEFE8FF);

  static List<BoxShadow> shadow(BuildContext c) => isDark(c)
      ? const []
      : [BoxShadow(color: const Color(0xFF5B21E6).withValues(alpha: 0.07), blurRadius: 18, offset: const Offset(0, 6))];

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final primary = dark ? accent : accentDeep;
    final onSurface = dark ? textDark : const Color(0xFF1A1228);
    final scheme = (dark
            ? ColorScheme.dark(
                primary: primary,
                onPrimary: Colors.white,
                secondary: accentHi,
                surface: surfaceDark,
                onSurface: textDark,
                error: bad,
                outline: lineDark,
                outlineVariant: lineDark,
                surfaceContainerHighest: surface2Dark,
              )
            : ColorScheme.light(primary: primary, onPrimary: Colors.white, surface: Colors.white, onSurface: onSurface, error: const Color(0xFFDC2626)));
    final pageBg = dark ? bg : const Color(0xFFF6F5FB);
    final lineC = dark ? lineDark : const Color(0xFFE8E4F0);
    final lineStrongC = dark ? lineStrongDark : const Color(0xFFD4CDE3);
    final surfaceC = dark ? surfaceDark : Colors.white;
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b, fontFamily: 'PlusJakartaSans');
    return base.copyWith(
      scaffoldBackgroundColor: pageBg,
      // Medium rather than regular for body text, so plain text is not thin. Anything that sets its own weight keeps it.
      textTheme: base.textTheme.apply(bodyColor: onSurface, displayColor: onSurface, fontFamily: 'PlusJakartaSans').copyWith(
            bodyLarge: base.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            bodyMedium: base.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            bodySmall: base.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            labelMedium: base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            labelSmall: base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
      iconTheme: IconThemeData(color: onSurface),
      dividerTheme: DividerThemeData(color: lineC, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: pageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: onSurface,
        titleTextStyle: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 18, fontWeight: FontWeight.w800, color: onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surfaceC,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: lineC)),
      ),
      // The Light / Dark / System choice in Account: the selected one in the app's purple, not the toolkit's default teal.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surfaceC,
          foregroundColor: onSurface,
          selectedBackgroundColor: dark ? accentSoft : const Color(0xFFEFE8FF),
          selectedForegroundColor: dark ? accentHi : accentDeep,
          side: BorderSide(color: lineStrongC),
          textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: lineC),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: dark ? accentHi : accentDeep, textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w600)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide(color: lineC),
        labelStyle: TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w500, fontSize: 14, color: onSurface),
        backgroundColor: surfaceC,
        selectedColor: primary,
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceC,
        hintStyle: TextStyle(color: dark ? faintDark : const Color(0xFF7A7490), fontWeight: FontWeight.w500),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: lineC)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: lineC)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primary, width: 1.5)),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: surfaceC, surfaceTintColor: Colors.transparent, modalBackgroundColor: surfaceC),
      dialogTheme: DialogThemeData(backgroundColor: surfaceC, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: lineC))),
      popupMenuTheme: PopupMenuThemeData(color: dark ? surface2Dark : Colors.white, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: lineStrongC))),
      snackBarTheme: SnackBarThemeData(backgroundColor: dark ? surface2Dark : const Color(0xFF1A1228), contentTextStyle: const TextStyle(fontFamily: 'PlusJakartaSans', color: Colors.white), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceC,
        indicatorColor: primary.withValues(alpha: 0.14),
        elevation: 8,
        labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

String rupees(num v) => v == v.roundToDouble() ? '₹${v.toStringAsFixed(0)}' : '₹${v.toStringAsFixed(2)}';
