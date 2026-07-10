import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DashCamTheme {
  final ThemeData light;
  final ThemeData dark;
  const DashCamTheme({required this.light, required this.dark});
}

DashCamTheme buildDashCamTheme() {
  const color = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFA6CE39), // Verde RGB(166, 206, 57)
    onPrimary: Colors.white,
    secondary: Color(0xFF6C7A91),
    onSecondary: Colors.white,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    surface: Color(0xFFF7F9FC),
    onSurface: Color(0xFF111827),
    tertiary: Color(0xFFA6CE39), // Verde RGB(166, 206, 57) para textos informativos
    onTertiary: Colors.white,
    surfaceVariant: Color(0xFFE5E7EB),
    onSurfaceVariant: Color(0xFF374151),
    outline: Color(0xFFCBD5E1),
    inverseSurface: Color(0xFF111827),
    onInverseSurface: Colors.white,
    primaryContainer: Color(0xFFE8F5D6), // Contenedor verde claro
    onPrimaryContainer: Color(0xFF4A5F1A), // Texto sobre contenedor verde
    secondaryContainer: Color(0xFFE8ECF3),
    onSecondaryContainer: Color(0xFF263244),
  );

  final baseText = GoogleFonts.interTextTheme();

  final light = ThemeData(
    useMaterial3: true,
    colorScheme: color,
    textTheme: baseText,
    scaffoldBackgroundColor: color.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: color.surface,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: baseText.titleMedium?.copyWith(
        color: color.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: color.primary.withOpacity(.12),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => baseText.labelMedium?.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
    ),
  );

  final dark = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark().copyWith(
      primary: const Color(0xFFA6CE39), // Verde RGB(166, 206, 57) para modo oscuro
      secondary: const Color(0xFF9AA4B2),
      surface: const Color(0xFF0B1220),
      onSurface: Colors.white,
      tertiary: const Color(0xFFA6CE39), // Verde RGB(166, 206, 57) para textos informativos
    ),
    textTheme: baseText,
  );

  return DashCamTheme(light: light, dark: dark);
}

