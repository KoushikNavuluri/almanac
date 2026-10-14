import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette: a broadsheet weather page's temperature bands ("Evening Star No. III").
/// Each colour has one job.
class C {
  static const navy = Color(0xFF172767); // ink, overnight, cold
  static const ink = Color(0xFF121838); // body text
  static const teal = Color(0xFF19798B); // calm, recovered, positive
  static const tealInk = Color(0xFF0F5A68);
  static const sun = Color(0xFFF3D567); // energy (fills only)
  static const amber = Color(0xFFEE9B43); // activity, warmth (fills only)
  static const amberInk = Color(0xFF9A4F06);
  static const coral = Color(0xFFE74B47); // "watch" fills
  static const crimson = Color(0xFFB80422); // lead: actions, masthead, warnings as text
  static const paper = Color(0xFFECEEF4); // cool newsprint, never cream
  static const card = Color(0xFFF8F9FC);
  static const muted = Color(0xFF535C80);
  static const rule = Color(0xFFCDD2E2);

  static Color group(String g) {
    switch (g) {
      case 'Heart':
        return crimson;
      case 'Day':
        return const Color(0xFFB0600C);
      case 'Fuel':
        return teal;
      default:
        return navy;
    }
  }
}

/// Type roles: Bebas Neue for statement numerals and headlines, Merriweather for the
/// forecaster's voice, Merriweather Sans for interface text.
class T {
  static TextStyle display(double size, {Color color = C.navy, double height = 0.92}) =>
      GoogleFonts.bebasNeue(fontSize: size, color: color, height: height, letterSpacing: 0.3);

  static TextStyle serif(double size, {Color color = C.ink, double height = 1.55, FontStyle? style, FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.merriweather(fontSize: size, color: color, height: height, fontStyle: style, fontWeight: weight);

  static TextStyle ui(double size, {Color color = C.ink, FontWeight weight = FontWeight.w600, double? height, double? spacing}) =>
      GoogleFonts.merriweatherSans(fontSize: size, color: color, fontWeight: weight, height: height, letterSpacing: spacing);

  static TextStyle kicker({Color color = C.muted, double size = 12}) =>
      GoogleFonts.merriweatherSans(fontSize: size, color: color, fontWeight: FontWeight.w800, letterSpacing: 1.6);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.crimson,
      primary: C.crimson,
      onPrimary: C.card,
      secondary: C.navy,
      surface: C.paper,
      onSurface: C.ink,
    ),
    scaffoldBackgroundColor: C.paper,
  );
  return base.copyWith(
    textTheme: GoogleFonts.merriweatherSansTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.navy),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.ink,
      behavior: SnackBarBehavior.floating,
      contentTextStyle: T.ui(14, color: C.card),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    dividerColor: C.rule,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(C.card),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.teal : C.rule),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.rule)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.rule)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: const BorderSide(color: C.crimson, width: 2)),
      hintStyle: T.ui(15, color: C.muted, weight: FontWeight.w400),
    ),
  );
}
