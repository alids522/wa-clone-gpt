import 'package:flutter/material.dart';

const brand = Color(0xFF2563EB);
const ice = Color(0xFF60A5FA);

ThemeData adoetzTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = Color(dark ? 0xFF080D18 : 0xFFF6F9FF);
  final surface = Color(dark ? 0xFF111B2C : 0xFFFFFFFF);
  final raised = Color(dark ? 0xFF172337 : 0xFFE9F0FA);
  final border = Color(dark ? 0xFF26354A : 0xFFDCE5F2);
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness)
      .copyWith(
        primary: dark ? ice : brand,
        onPrimary: dark ? const Color(0xFF080D18) : Colors.white,
        surface: surface,
        onSurface: Color(dark ? 0xFFF8FAFC : 0xFF0F172A),
        onSurfaceVariant: Color(dark ? 0xFF94A3B8 : 0xFF64748B),
        outline: border,
        surfaceContainerHighest: raised,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: 'sans-serif',
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    dividerColor: border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: raised,
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ice, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 54),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: brand.withValues(alpha: .18),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: raised,
      contentTextStyle: TextStyle(color: scheme.onSurface),
    ),
  );
}
