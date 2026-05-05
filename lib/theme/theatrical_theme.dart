// V1 Theatrical — velvet + warm gold. Dramatic, serif-forward.
// Fonts: Playfair Display (headings) + Raleway (body).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

ThemeData get theatricalTheme {
  const cs = ColorScheme(
    brightness: Brightness.dark,
    primary: TheatricalColors.footlight,
    onPrimary: TheatricalColors.background,
    primaryContainer: TheatricalColors.footlightDim,
    onPrimaryContainer: TheatricalColors.ivory,
    secondary: TheatricalColors.gold,
    onSecondary: TheatricalColors.background,
    secondaryContainer: TheatricalColors.curtain,
    onSecondaryContainer: TheatricalColors.ivory,
    tertiary: TheatricalColors.rose,
    onTertiary: TheatricalColors.ivory,
    tertiaryContainer: TheatricalColors.velvet,
    onTertiaryContainer: TheatricalColors.ivory,
    error: TheatricalColors.danger,
    onError: TheatricalColors.ivory,
    errorContainer: Color(0xFF3A1010),
    onErrorContainer: TheatricalColors.danger,
    surface: TheatricalColors.velvet,
    onSurface: TheatricalColors.ivory,
    surfaceContainerHighest: TheatricalColors.curtain,
    surfaceContainerHigh: TheatricalColors.curtain,
    surfaceContainer: TheatricalColors.velvet,
    surfaceContainerLow: TheatricalColors.background,
    surfaceContainerLowest: TheatricalColors.background,
    outline: TheatricalColors.ivoryGhost,
    outlineVariant: TheatricalColors.goldSoft,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: TheatricalColors.ivory,
    onInverseSurface: TheatricalColors.background,
    inversePrimary: TheatricalColors.footlightDim,
  );

  final bodyFont = GoogleFonts.raleway;
  final displayFont = GoogleFonts.playfairDisplay;

  final textTheme = TextTheme(
    displayLarge: displayFont(fontSize: 57, fontWeight: FontWeight.w900, color: TheatricalColors.ivory),
    displayMedium: displayFont(fontSize: 45, fontWeight: FontWeight.w800, color: TheatricalColors.ivory),
    displaySmall: displayFont(fontSize: 36, fontWeight: FontWeight.w700, color: TheatricalColors.ivory),
    headlineLarge: displayFont(fontSize: 32, fontWeight: FontWeight.w700, color: TheatricalColors.ivory, letterSpacing: 0.5),
    headlineMedium: displayFont(fontSize: 22, fontWeight: FontWeight.w700, color: TheatricalColors.ivory, letterSpacing: 0.5),
    headlineSmall: displayFont(fontSize: 18, fontWeight: FontWeight.w600, color: TheatricalColors.ivory),
    titleLarge: displayFont(fontSize: 18, fontWeight: FontWeight.w600, color: TheatricalColors.ivory),
    titleMedium: bodyFont(fontSize: 16, fontWeight: FontWeight.w600, color: TheatricalColors.ivory),
    titleSmall: bodyFont(fontSize: 14, fontWeight: FontWeight.w600, color: TheatricalColors.ivoryMuted),
    bodyLarge: bodyFont(fontSize: 16, fontWeight: FontWeight.w400, color: TheatricalColors.ivory),
    bodyMedium: bodyFont(fontSize: 14, fontWeight: FontWeight.w400, color: TheatricalColors.ivoryMuted),
    bodySmall: bodyFont(fontSize: 12, fontWeight: FontWeight.w400, color: TheatricalColors.ivoryGhost),
    labelLarge: bodyFont(fontSize: 16, fontWeight: FontWeight.w700, color: TheatricalColors.background),
    labelMedium: bodyFont(fontSize: 13, fontWeight: FontWeight.w500, color: TheatricalColors.ivoryMuted),
    labelSmall: bodyFont(fontSize: 11, fontWeight: FontWeight.w500, color: TheatricalColors.ivoryGhost),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: cs,
    textTheme: textTheme,
    scaffoldBackgroundColor: TheatricalColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: TheatricalColors.background,
      foregroundColor: TheatricalColors.ivory,
      elevation: 0,
      shadowColor: Colors.transparent,
      titleTextStyle: displayFont(
        fontSize: 22, fontWeight: FontWeight.w700,
        color: TheatricalColors.ivory, letterSpacing: 0.5,
      ),
      iconTheme: const IconThemeData(color: TheatricalColors.gold),
    ),
    cardTheme: CardThemeData(
      color: TheatricalColors.velvet,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TheatricalRadius.lg),
        side: BorderSide(color: TheatricalColors.gold.withOpacity(0.1), width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TheatricalColors.footlight,
        foregroundColor: TheatricalColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TheatricalRadius.lg)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        textStyle: displayFont(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TheatricalColors.ivory,
        side: BorderSide(color: TheatricalColors.gold.withOpacity(0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TheatricalRadius.md)),
        textStyle: bodyFont(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: TheatricalColors.footlight,
        textStyle: bodyFont(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? TheatricalColors.footlight : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? TheatricalColors.footlightDim : null),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? TheatricalColors.footlight : TheatricalColors.ivoryGhost),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? TheatricalColors.footlight : null),
    ),
    dividerTheme: DividerThemeData(
      color: TheatricalColors.gold.withOpacity(0.15),
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TheatricalColors.velvet,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TheatricalRadius.md),
        borderSide: BorderSide(color: TheatricalColors.gold.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TheatricalRadius.md),
        borderSide: BorderSide(color: TheatricalColors.gold.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TheatricalRadius.md),
        borderSide: const BorderSide(color: TheatricalColors.footlight, width: 2),
      ),
      labelStyle: bodyFont(color: TheatricalColors.ivoryMuted, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: TheatricalColors.curtain,
      contentTextStyle: bodyFont(color: TheatricalColors.ivory, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TheatricalRadius.md)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: TheatricalColors.velvet,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TheatricalRadius.lg)),
      titleTextStyle: displayFont(fontSize: 18, fontWeight: FontWeight.w700, color: TheatricalColors.ivory),
      contentTextStyle: bodyFont(fontSize: 14, color: TheatricalColors.ivoryMuted),
    ),
    listTileTheme: ListTileThemeData(
      textColor: TheatricalColors.ivory,
      iconColor: TheatricalColors.gold,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TheatricalRadius.md)),
    ),
    iconTheme: const IconThemeData(color: TheatricalColors.gold),
  );
}
