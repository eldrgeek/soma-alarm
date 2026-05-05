// V3 Mike Special (The Forge) — carbon + ember. Default Pulse style.
// Fonts: Fraunces (display/logo) + Space Grotesk (body/UI).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

ThemeData get mikeSpecialTheme {
  const cs = ColorScheme(
    brightness: Brightness.dark,
    primary: MikeSpecialColors.ember,
    onPrimary: Colors.white,
    primaryContainer: MikeSpecialColors.emberDeep,
    onPrimaryContainer: Colors.white,
    secondary: MikeSpecialColors.molten,
    onSecondary: MikeSpecialColors.carbon,
    secondaryContainer: MikeSpecialColors.graphiteLighter,
    onSecondaryContainer: MikeSpecialColors.steel,
    tertiary: MikeSpecialColors.electric,
    onTertiary: MikeSpecialColors.carbon,
    tertiaryContainer: MikeSpecialColors.graphiteLight,
    onTertiaryContainer: MikeSpecialColors.electric,
    error: MikeSpecialColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFF4D1414),
    onErrorContainer: MikeSpecialColors.danger,
    surface: MikeSpecialColors.graphite,
    onSurface: MikeSpecialColors.steel,
    surfaceContainerHighest: MikeSpecialColors.graphiteLight,
    surfaceContainerHigh: MikeSpecialColors.graphiteLight,
    surfaceContainer: MikeSpecialColors.graphite,
    surfaceContainerLow: MikeSpecialColors.carbon,
    surfaceContainerLowest: MikeSpecialColors.background,
    outline: MikeSpecialColors.steelGhost,
    outlineVariant: MikeSpecialColors.graphiteLighter,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: MikeSpecialColors.steel,
    onInverseSurface: MikeSpecialColors.carbon,
    inversePrimary: MikeSpecialColors.emberDeep,
  );

  final bodyFont = GoogleFonts.spaceGrotesk;
  final displayFont = GoogleFonts.fraunces;

  final textTheme = TextTheme(
    displayLarge: displayFont(fontSize: 57, fontWeight: FontWeight.w900, color: MikeSpecialColors.ember, letterSpacing: -2),
    displayMedium: displayFont(fontSize: 45, fontWeight: FontWeight.w800, color: MikeSpecialColors.steel, letterSpacing: -1),
    displaySmall: displayFont(fontSize: 36, fontWeight: FontWeight.w700, color: MikeSpecialColors.steel),
    headlineLarge: bodyFont(fontSize: 32, fontWeight: FontWeight.w900, color: MikeSpecialColors.ember, letterSpacing: -1),
    headlineMedium: bodyFont(fontSize: 22, fontWeight: FontWeight.w700, color: MikeSpecialColors.steel),
    headlineSmall: bodyFont(fontSize: 18, fontWeight: FontWeight.w700, color: MikeSpecialColors.steel),
    titleLarge: bodyFont(fontSize: 18, fontWeight: FontWeight.w600, color: MikeSpecialColors.steel),
    titleMedium: bodyFont(fontSize: 16, fontWeight: FontWeight.w600, color: MikeSpecialColors.steel),
    titleSmall: bodyFont(fontSize: 14, fontWeight: FontWeight.w600, color: MikeSpecialColors.steelDim),
    bodyLarge: bodyFont(fontSize: 16, fontWeight: FontWeight.w400, color: MikeSpecialColors.steel),
    bodyMedium: bodyFont(fontSize: 14, fontWeight: FontWeight.w400, color: MikeSpecialColors.steelDim),
    bodySmall: bodyFont(fontSize: 12, fontWeight: FontWeight.w400, color: MikeSpecialColors.steelGhost),
    labelLarge: bodyFont(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
    labelMedium: bodyFont(fontSize: 13, fontWeight: FontWeight.w500, color: MikeSpecialColors.steelDim),
    labelSmall: bodyFont(fontSize: 11, fontWeight: FontWeight.w500, color: MikeSpecialColors.steelGhost),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: cs,
    textTheme: textTheme,
    scaffoldBackgroundColor: MikeSpecialColors.scaffold,
    appBarTheme: AppBarTheme(
      backgroundColor: MikeSpecialColors.carbon,
      foregroundColor: MikeSpecialColors.steel,
      elevation: 0,
      shadowColor: Colors.transparent,
      titleTextStyle: displayFont(
        fontSize: 22, fontWeight: FontWeight.w900,
        color: MikeSpecialColors.ember, letterSpacing: -0.5,
      ),
      iconTheme: const IconThemeData(color: MikeSpecialColors.steelDim),
    ),
    cardTheme: CardThemeData(
      color: MikeSpecialColors.graphiteLight,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MikeSpecialRadius.lg),
        side: const BorderSide(color: MikeSpecialColors.emberGlow, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MikeSpecialColors.ember,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MikeSpecialRadius.md)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        textStyle: bodyFont(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MikeSpecialColors.steel,
        side: const BorderSide(color: MikeSpecialColors.steelGhost),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MikeSpecialRadius.md)),
        textStyle: bodyFont(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MikeSpecialColors.ember,
        textStyle: bodyFont(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? MikeSpecialColors.ember : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? MikeSpecialColors.emberDeep : null),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? MikeSpecialColors.ember : MikeSpecialColors.steelGhost),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? MikeSpecialColors.ember : null),
    ),
    dividerTheme: const DividerThemeData(
      color: MikeSpecialColors.graphiteLighter,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MikeSpecialColors.graphiteLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MikeSpecialRadius.md),
        borderSide: const BorderSide(color: MikeSpecialColors.steelGhost),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MikeSpecialRadius.md),
        borderSide: const BorderSide(color: MikeSpecialColors.steelGhost),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MikeSpecialRadius.md),
        borderSide: const BorderSide(color: MikeSpecialColors.ember, width: 2),
      ),
      labelStyle: bodyFont(color: MikeSpecialColors.steelDim, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MikeSpecialColors.graphiteLight,
      contentTextStyle: bodyFont(color: MikeSpecialColors.steel, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MikeSpecialRadius.sm)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MikeSpecialColors.graphite,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MikeSpecialRadius.lg)),
      titleTextStyle: bodyFont(fontSize: 18, fontWeight: FontWeight.w700, color: MikeSpecialColors.steel),
      contentTextStyle: bodyFont(fontSize: 14, color: MikeSpecialColors.steelDim),
    ),
    listTileTheme: ListTileThemeData(
      textColor: MikeSpecialColors.steel,
      iconColor: MikeSpecialColors.steelDim,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MikeSpecialRadius.sm)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: bodyFont(fontSize: 14, color: MikeSpecialColors.steel),
    ),
    iconTheme: const IconThemeData(color: MikeSpecialColors.steelDim),
  );
}
