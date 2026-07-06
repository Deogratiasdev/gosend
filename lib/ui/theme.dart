import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Palette warm grayscale ──────────────────────────────────────
  // Light: warm cream-white, not blinding pure white
  static const Color _lightBackground = Color(0xFFFAF9F7);
  static const Color _lightSurface    = Color(0xFFFFFFFF);
  static const Color _lightOnSurface  = Color(0xFF1C1C1C);
  static const Color _lightSubtle     = Color(0xFF8A8A8A);
  static const Color _lightDivider    = Color(0xFFE8E6E1);

  // Dark: warm charcoal, not pitch black
  static const Color _darkBackground  = Color(0xFF141414);
  static const Color _darkSurface     = Color(0xFF1E1E1E);
  static const Color _darkOnSurface   = Color(0xFFF0EFED);
  static const Color _darkSubtle      = Color(0xFF6E6E6E);
  static const Color _darkDivider     = Color(0xFF2C2C2C);

  // Accent: neutral gray with slight warmth
  static const Color _accentLight     = Color(0xFF2A2A2A);
  static const Color _accentDark      = Color(0xFFE8E7E5);

  // ── Text theme ─────────────────────────────────────────────────
  static final TextTheme _textTheme = TextTheme(
    displayLarge:  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
    displayMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    displaySmall:  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    headlineMedium:GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    headlineSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    titleLarge:    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    titleMedium:   GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
    titleSmall:    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
    bodyLarge:     GoogleFonts.inter(),
    bodyMedium:    GoogleFonts.inter(),
    bodySmall:     GoogleFonts.inter(),
    labelLarge:    GoogleFonts.inter(fontWeight: FontWeight.w500),
    labelMedium:   GoogleFonts.inter(),
    labelSmall:    GoogleFonts.inter(),
  );

  // ── Light theme ────────────────────────────────────────────────
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary:             _accentLight,
      onPrimary:           Colors.white,
      surface:             _lightSurface,
      onSurface:           _lightOnSurface,
      onSurfaceVariant:    _lightSubtle,
      outlineVariant:       _lightDivider,
      surfaceContainerLow: _lightBackground,
    ),
    scaffoldBackgroundColor: _lightBackground,
    useMaterial3: true,
    textTheme: _textTheme.apply(
      bodyColor: _lightOnSurface,
      displayColor: _lightOnSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _lightBackground,
      foregroundColor: _lightOnSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: _lightOnSurface),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: _lightOnSurface, fontSize: 20, fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: _lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _lightDivider),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: _lightDivider,
      thickness: 1,
    ),
    iconTheme: const IconThemeData(color: _lightOnSurface),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _accentLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _accentLight,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _accentLight,
        side: const BorderSide(color: _lightDivider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: _lightOnSurface, fontSize: 18, fontWeight: FontWeight.w700,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _darkSurface,
      contentTextStyle: GoogleFonts.inter(color: _darkOnSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightDivider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accentLight, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _accentLight,
      linearTrackColor: _lightDivider,
      circularTrackColor: _lightDivider,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: _lightOnSurface,
      textColor: _lightOnSurface,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: _lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );

  // ── Dark theme ─────────────────────────────────────────────────
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary:             _accentDark,
      onPrimary:           _darkBackground,
      surface:             _darkSurface,
      onSurface:           _darkOnSurface,
      onSurfaceVariant:    _darkSubtle,
      outlineVariant:      _darkDivider,
      surfaceContainerLow: _darkBackground,
    ),
    scaffoldBackgroundColor: _darkBackground,
    useMaterial3: true,
    textTheme: _textTheme.apply(
      bodyColor: _darkOnSurface,
      displayColor: _darkOnSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _darkBackground,
      foregroundColor: _darkOnSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: const IconThemeData(color: _darkOnSurface),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: _darkOnSurface, fontSize: 20, fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: _darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _darkDivider),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: _darkDivider,
      thickness: 1,
    ),
    iconTheme: const IconThemeData(color: _darkOnSurface),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _accentDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _accentDark,
        foregroundColor: _darkBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _accentDark,
        side: const BorderSide(color: _darkDivider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: _darkOnSurface, fontSize: 18, fontWeight: FontWeight.w700,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _lightSurface,
      contentTextStyle: GoogleFonts.inter(color: _lightOnSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkDivider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accentDark, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _accentDark,
      linearTrackColor: _darkDivider,
      circularTrackColor: _darkDivider,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: _darkOnSurface,
      textColor: _darkOnSurface,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: _darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}
