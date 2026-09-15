import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const ink = Color(0xFF201C1D);
  static const inkSoft = Color(0xFF3D393A);
  static const gold = Color(0xFFFFC744);
  static const goldSoft = Color(0xFFFFE8A8);
  static const ivory = Color(0xFFF4F1E8);
  static const paper = Color(0xFFFFFDF8);
  static const night = Color(0xFF171415);
  static const nightPaper = Color(0xFF242021);
  static const green = Color(0xFF2F8F64);

  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? nightPaper : paper;
    final background = dark ? night : ivory;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: dark ? gold : ink,
      onPrimary: dark ? ink : Colors.white,
      primaryContainer: goldSoft,
      onPrimaryContainer: ink,
      secondary: gold,
      onSecondary: ink,
      secondaryContainer: goldSoft,
      onSecondaryContainer: ink,
      error: const Color(0xFFD84A4A),
      onError: Colors.white,
      surface: surface,
      onSurface: dark ? const Color(0xFFF8F4EA) : ink,
      surfaceContainerHighest: dark ? inkSoft : const Color(0xFFEAE6DC),
      onSurfaceVariant: dark
          ? const Color(0xFFC9C2B8)
          : const Color(0xFF716B67),
      outline: dark ? const Color(0xFF514B4C) : const Color(0xFFD8D1C5),
      outlineVariant: dark ? const Color(0xFF393435) : const Color(0xFFE8E1D5),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? ivory : ink,
      onInverseSurface: dark ? ink : Colors.white,
      inversePrimary: gold,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Tajawal',
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
    );
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 38,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.05,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: -.6,
        height: 1.15,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 25,
        fontWeight: FontWeight.w800,
        letterSpacing: -.35,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
    );
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 72,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? gold : ink,
          foregroundColor: dark ? ink : Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: gold, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        selectedColor: gold,
        backgroundColor: surface,
        labelStyle: TextStyle(
          color: dark ? const Color(0xFFF8F4EA) : ink,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
        ),
        checkmarkColor: ink,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? ivory : ink,
        contentTextStyle: TextStyle(color: dark ? ink : Colors.white),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: gold,
        linearTrackColor: Color(0x33FFFFFF),
      ),
    );
  }
}
