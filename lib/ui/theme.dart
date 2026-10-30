import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Thème GoSend - palette verte cohérente.
///
/// Rôle de chaque couleur (à respecter dans tout le code) :
/// - primary (vert) : actions principales, boutons Envoyer, sélection.
/// - secondary (teal) : fichiers, dossiers, infos secondaires.
/// - tertiary (orange) : attente / recherche, accents chauds.
/// - success (vert) : réseau actif, transferts terminés.
/// - fileType : rose = photos, violet = vidéos, cyan = audio, vert = autres.
class AppTheme {
  // ── Light ──────────────────────────────────────────────────────
  static const Color _lightPrimary = Color(0xFF15803D);
  static const Color _lightOnPrimary = Colors.white;
  static const Color _lightPrimaryContainer = Color(0xFFDCFCE7);
  static const Color _lightOnPrimaryContainer = Color(0xFF14532D);
  static const Color _lightSecondary = Color(0xFF0D9488);
  static const Color _lightSecondaryContainer = Color(0xFFCCFBF1);
  static const Color _lightTertiary = Color(0xFFEA580C);
  static const Color _lightTertiaryContainer = Color(0xFFFFEDD5);

  static const Color _lightBackground = Color(0xFFF4F8F4);
  static const Color _lightSurface = Colors.white;
  static const Color _lightOnSurface = Color(0xFF122117);
  static const Color _lightSubtle = Color(0xFF5F6F60);
  static const Color _lightDivider = Color(0xFFDDE8DE);

  // ── Dark ───────────────────────────────────────────────────────
  static const Color _darkPrimary = Color(0xFF4ADE80);
  static const Color _darkOnPrimary = Color(0xFF052E16);
  static const Color _darkPrimaryContainer = Color(0xFF14532D);
  static const Color _darkOnPrimaryContainer = Color(0xFFDCFCE7);
  static const Color _darkSecondary = Color(0xFF2DD4BF);
  static const Color _darkSecondaryContainer = Color(0xFF134E4A);
  static const Color _darkTertiary = Color(0xFFFB923C);
  static const Color _darkTertiaryContainer = Color(0xFF7C2D12);

  static const Color _darkBackground = Color(0xFF0D120E);
  static const Color _darkSurface = Color(0xFF151D17);
  static const Color _darkOnSurface = Color(0xFFEBF3EC);
  static const Color _darkSubtle = Color(0xFF9DAD9E);
  static const Color _darkDivider = Color(0xFF243024);

  // ── Utilitaires ────────────────────────────────────────────────
  static const Color success = Color(0xFF15803D);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color photoColor = Color(0xFFDB2777);
  static const Color videoColor = Color(0xFF7C3AED);
  static const Color audioColor = Color(0xFF0891B2);
  static const Color fileColor = Color(0xFF15803D);

  static Color fileTypeColor(String ext) {
    final e = ext.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg']
        .contains(e)) {
      return photoColor;
    }
    if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', '3gp']
        .contains(e)) {
      return videoColor;
    }
    if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'].contains(e)) {
      return audioColor;
    }
    return fileColor;
  }

  // ── Texte ──────────────────────────────────────────────────────
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
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: _lightPrimary,
      onPrimary: _lightOnPrimary,
      primaryContainer: _lightPrimaryContainer,
      onPrimaryContainer: _lightOnPrimaryContainer,
      secondary: _lightSecondary,
      onSecondary: Colors.white,
      secondaryContainer: _lightSecondaryContainer,
      tertiary: _lightTertiary,
      tertiaryContainer: _lightTertiaryContainer,
      surface: _lightSurface,
      onSurface: _lightOnSurface,
      onSurfaceVariant: _lightSubtle,
      outlineVariant: _lightDivider,
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
    dividerTheme: const DividerThemeData(color: _lightDivider, thickness: 1),
    iconTheme: const IconThemeData(color: _lightOnSurface),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _lightPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _lightPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _lightPrimary,
        side: const BorderSide(color: _lightPrimary, width: 1.2),
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
      backgroundColor: _lightOnSurface,
      contentTextStyle: GoogleFonts.inter(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
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
        borderSide: const BorderSide(color: _lightPrimary, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _lightPrimary,
      linearTrackColor: _lightDivider,
      circularTrackColor: _lightDivider,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: _lightPrimary,
      textColor: _lightOnSurface,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: _lightPrimaryContainer,
      labelStyle: TextStyle(color: _lightOnPrimaryContainer),
      secondaryLabelStyle: TextStyle(color: _lightOnPrimaryContainer),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: _darkPrimary,
      onPrimary: _darkOnPrimary,
      primaryContainer: _darkPrimaryContainer,
      onPrimaryContainer: _darkOnPrimaryContainer,
      secondary: _darkSecondary,
      secondaryContainer: _darkSecondaryContainer,
      tertiary: _darkTertiary,
      tertiaryContainer: _darkTertiaryContainer,
      surface: _darkSurface,
      onSurface: _darkOnSurface,
      onSurfaceVariant: _darkSubtle,
      outlineVariant: _darkDivider,
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
    dividerTheme: const DividerThemeData(color: _darkDivider, thickness: 1),
    iconTheme: const IconThemeData(color: _darkOnSurface),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _darkPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _darkPrimary,
        foregroundColor: _darkOnPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _darkPrimary,
        side: const BorderSide(color: _darkPrimary, width: 1.2),
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
      backgroundColor: _darkOnSurface,
      contentTextStyle: GoogleFonts.inter(color: _darkBackground),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkSurface,
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
        borderSide: const BorderSide(color: _darkPrimary, width: 1.5),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _darkPrimary,
      linearTrackColor: _darkDivider,
      circularTrackColor: _darkDivider,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: _darkPrimary,
      textColor: _darkOnSurface,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: _darkPrimaryContainer,
      labelStyle: TextStyle(color: _darkOnPrimaryContainer),
      secondaryLabelStyle: TextStyle(color: _darkOnPrimaryContainer),
    ),
  );
}
