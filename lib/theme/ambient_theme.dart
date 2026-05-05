// V2 Ambient — midnight blues + dawn pinks. Calm, breath-inspired.
// Fonts: Cormorant Garamond (headings) + DM Sans (body).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

ThemeData get ambientTheme {
  const cs = ColorScheme(
    brightness: Brightness.dark,
    primary: AmbientColors.dawnPink,
    onPrimary: AmbientColors.midnight,
    primaryContainer: AmbientColors.twilight,
    onPrimaryContainer: AmbientColors.dawnPink,
    secondary: AmbientColors.dawnPeach,
    onSecondary: AmbientColors.midnight,
    secondaryContainer: AmbientColors.dusk,
    onSecondaryContainer: AmbientColors.moon,
    tertiary: AmbientColors.moon,
    onTertiary: AmbientColors.midnight,
    tertiaryContainer: AmbientColors.twilight,
    onTertiaryContainer: AmbientColors.moon,
    error: AmbientColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFF3D1515),
    onErrorContainer: AmbientColors.danger,
    surface: AmbientColors.twilight,
    onSurface: AmbientColors.moon,
    surfaceContainerHighest: AmbientColors.dusk,
    surfaceContainerHigh: AmbientColors.dusk,
    surfaceContainer: AmbientColors.twilight,
    surfaceContainerLow: AmbientColors.deepSea,
    surfaceContainerLowest: AmbientColors.background,
    outline: AmbientColors.moonGhost,
    outlineVariant: AmbientColors.dawnRose,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: AmbientColors.moon,
    onInverseSurface: AmbientColors.midnight,
    inversePrimary: AmbientColors.dawnPink,
  );

  final bodyFont = GoogleFonts.dmSans;
  final displayFont = GoogleFonts.cormorantGaramond;

  final textTheme = TextTheme(
    displayLarge: displayFont(fontSize: 57, fontWeight: FontWeight.w300, color: AmbientColors.moon, letterSpacing: 4),
    displayMedium: displayFont(fontSize: 45, fontWeight: FontWeight.w300, color: AmbientColors.moon, letterSpacing: 3),
    displaySmall: displayFont(fontSize: 36, fontWeight: FontWeight.w300, color: AmbientColors.moon, letterSpacing: 2),
    headlineLarge: displayFont(fontSize: 32, fontWeight: FontWeight.w600, color: AmbientColors.moon, letterSpacing: 2),
    headlineMedium: displayFont(fontSize: 24, fontWeight: FontWeight.w300, color: AmbientColors.moon, letterSpacing: 2),
    headlineSmall: displayFont(fontSize: 20, fontWeight: FontWeight.w600, color: AmbientColors.moon),
    titleLarge: bodyFont(fontSize: 18, fontWeight: FontWeight.w500, color: AmbientColors.moon),
    titleMedium: bodyFont(fontSize: 16, fontWeight: FontWeight.w500, color: AmbientColors.moon),
    titleSmall: bodyFont(fontSize: 14, fontWeight: FontWeight.w500, color: AmbientColors.moonDim),
    bodyLarge: bodyFont(fontSize: 16, fontWeight: FontWeight.w400, color: AmbientColors.moon),
    bodyMedium: bodyFont(fontSize: 14, fontWeight: FontWeight.w400, color: AmbientColors.moonDim),
    bodySmall: bodyFont(fontSize: 12, fontWeight: FontWeight.w400, color: AmbientColors.moonGhost),
    labelLarge: bodyFont(fontSize: 15, fontWeight: FontWeight.w600, color: AmbientColors.midnight),
    labelMedium: bodyFont(fontSize: 13, fontWeight: FontWeight.w500, color: AmbientColors.moonDim),
    labelSmall: bodyFont(fontSize: 11, fontWeight: FontWeight.w500, color: AmbientColors.moonGhost),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: cs,
    textTheme: textTheme,
    scaffoldBackgroundColor: AmbientColors.midnight,
    appBarTheme: AppBarTheme(
      backgroundColor: AmbientColors.midnight,
      foregroundColor: AmbientColors.moon,
      elevation: 0,
      shadowColor: Colors.transparent,
      titleTextStyle: displayFont(
        fontSize: 24, fontWeight: FontWeight.w300,
        color: AmbientColors.moon, letterSpacing: 2,
      ),
      iconTheme: const IconThemeData(color: AmbientColors.moonDim),
    ),
    cardTheme: CardThemeData(
      color: AmbientColors.twilight,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AmbientRadius.lg),
        side: BorderSide(color: AmbientColors.moon.withOpacity(0.05), width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AmbientColors.dawnPink,
        foregroundColor: AmbientColors.midnight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        textStyle: bodyFont(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AmbientColors.moonDim,
        side: BorderSide(color: AmbientColors.moon.withOpacity(0.08)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: bodyFont(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AmbientColors.dawnPink,
        textStyle: bodyFont(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AmbientColors.dawnPink : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AmbientColors.dawnPink.withOpacity(0.4) : null),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AmbientColors.dawnPink : AmbientColors.moonGhost),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AmbientColors.dawnPink : null),
    ),
    dividerTheme: DividerThemeData(
      color: AmbientColors.moon.withOpacity(0.06),
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AmbientColors.twilight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AmbientRadius.md),
        borderSide: BorderSide(color: AmbientColors.moon.withOpacity(0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AmbientRadius.md),
        borderSide: BorderSide(color: AmbientColors.moon.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AmbientRadius.md),
        borderSide: const BorderSide(color: AmbientColors.dawnPink, width: 1.5),
      ),
      labelStyle: bodyFont(color: AmbientColors.moonDim, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AmbientColors.twilight,
      contentTextStyle: bodyFont(color: AmbientColors.moon, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AmbientRadius.lg)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AmbientColors.twilight,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: displayFont(fontSize: 20, fontWeight: FontWeight.w600, color: AmbientColors.moon, letterSpacing: 1),
      contentTextStyle: bodyFont(fontSize: 14, color: AmbientColors.moonDim),
    ),
    listTileTheme: ListTileThemeData(
      textColor: AmbientColors.moon,
      iconColor: AmbientColors.dawnPink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AmbientRadius.md)),
    ),
    iconTheme: const IconThemeData(color: AmbientColors.moonDim),
  );
}
