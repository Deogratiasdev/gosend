import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final TextTheme _textTheme = TextTheme(
    displayLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
    displayMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    displaySmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    headlineLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
    headlineMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    headlineSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    titleLarge: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
    titleMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
    titleSmall: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
    bodyLarge: GoogleFonts.inter(),
    bodyMedium: GoogleFonts.inter(),
    bodySmall: GoogleFonts.inter(),
    labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w500),
    labelMedium: GoogleFonts.inter(),
    labelSmall: GoogleFonts.inter(),
  );

  static final ThemeData lightTheme = ThemeData(
    colorScheme: const ColorScheme.light(
      primary: Colors.black,
      surface: Color(0xFFF7F7F7),
      onSurface: Color(0xFF111111),
      onSurfaceVariant: Color(0xFF666666),
      outlineVariant: Color(0xFFDDDDDD),
    ),
    scaffoldBackgroundColor: Colors.white,
    useMaterial3: true,
    textTheme: _textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.black),
      titleTextStyle: GoogleFonts.plusJakartaSans(
          color: Colors.black, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFEEEEEE))),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      surface: Color(0xFF1A1A1A),
      onSurface: Colors.white,
      onSurfaceVariant: Color(0xFFA0A0A0),
      outlineVariant: Color(0xFF2E2E2E),
    ),
    scaffoldBackgroundColor: const Color(0xFF0F0F0F),
    useMaterial3: true,
    textTheme: _textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF0F0F0F),
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: GoogleFonts.plusJakartaSans(
          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1A1A),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2E2E))),
    ),
  );
}
