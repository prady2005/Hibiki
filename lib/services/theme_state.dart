import 'package:flutter/material.dart';

enum AppThemeChoice {
  systemDefault,
  dark,
  light,
  cherryBlossom,
  coffee,
  materialDesign3,
}

final appThemeChoiceNotifier = ValueNotifier<AppThemeChoice>(
  AppThemeChoice.systemDefault,
);

class AppThemePalette {
  const AppThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.accentAlt,
    required this.border,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color text;
  final Color mutedText;
  final Color accent;
  final Color accentAlt;
  final Color border;
}

String appThemeChoiceLabel(AppThemeChoice choice) {
  switch (choice) {
    case AppThemeChoice.systemDefault:
      return 'System default';
    case AppThemeChoice.dark:
      return 'Dark mode';
    case AppThemeChoice.light:
      return 'Light mode';
    case AppThemeChoice.cherryBlossom:
      return 'Cherry blossom';
    case AppThemeChoice.coffee:
      return 'Coffee';
    case AppThemeChoice.materialDesign3:
      return 'Material Design 3';
  }
}

ThemeMode themeModeForChoice(AppThemeChoice choice) {
  switch (choice) {
    case AppThemeChoice.systemDefault:
      return ThemeMode.system;
    case AppThemeChoice.dark:
      return ThemeMode.dark;
    case AppThemeChoice.light:
    case AppThemeChoice.cherryBlossom:
    case AppThemeChoice.coffee:
    case AppThemeChoice.materialDesign3:
      return ThemeMode.light;
  }
}

ThemeData lightAppTheme(AppThemeChoice choice) {
  final AppThemePalette palette = paletteForChoice(choice, Brightness.light);
  return _themeFromPalette(palette, Brightness.light);
}

ThemeData darkAppTheme(AppThemeChoice choice) {
  final AppThemePalette palette = paletteForChoice(choice, Brightness.dark);
  return _themeFromPalette(palette, Brightness.dark);
}

AppThemePalette paletteForChoice(AppThemeChoice choice, Brightness brightness) {
  switch (choice) {
    case AppThemeChoice.systemDefault:
      return brightness == Brightness.dark ? _darkPalette : _lightPalette;
    case AppThemeChoice.dark:
      return _darkPalette;
    case AppThemeChoice.light:
      return _lightPalette;
    case AppThemeChoice.cherryBlossom:
      return _cherryBlossomPalette;
    case AppThemeChoice.coffee:
      return _coffeePalette;
    case AppThemeChoice.materialDesign3:
      return brightness == Brightness.dark ? _materialDarkPalette : _materialLightPalette;
  }
}

AppThemePalette activeAppPalette(BuildContext context) {
  final AppThemeChoice choice = appThemeChoiceNotifier.value;
  final Brightness platformBrightness = MediaQuery.platformBrightnessOf(context);
  final Brightness brightness = choice == AppThemeChoice.systemDefault
      ? platformBrightness
      : choice == AppThemeChoice.dark
          ? Brightness.dark
          : Brightness.light;
  return paletteForChoice(choice, brightness);
}

Color readableTextOn(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : const Color(0xFF111111);
}

ThemeData _themeFromPalette(AppThemePalette palette, Brightness brightness) {
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    fontFamily: 'SF Pro Display',
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      primary: palette.accent,
      secondary: palette.accentAlt,
      surface: palette.surface,
    ),
  );
}

const AppThemePalette _darkPalette = AppThemePalette(
  background: Color(0xFF0E0E0E),
  surface: Color(0xFF171717),
  surfaceAlt: Color(0xFF242424),
  text: Colors.white,
  mutedText: Color(0xFF8C8C8C),
  accent: Colors.white,
  accentAlt: Color(0xFFBDBDBD),
  border: Color(0x1AFFFFFF),
);

const AppThemePalette _lightPalette = AppThemePalette(
  background: Color(0xFFF7F7F8),
  surface: Colors.white,
  surfaceAlt: Color(0xFFECEDEF),
  text: Color(0xFF111111),
  mutedText: Color(0xFF636363),
  accent: Color(0xFF111111),
  accentAlt: Color(0xFF6D6D6D),
  border: Color(0x1F000000),
);

const AppThemePalette _cherryBlossomPalette = AppThemePalette(
  background: Color(0xFFFFF5F8),
  surface: Color(0xFFFFE6EE),
  surfaceAlt: Color(0xFFFFCEDC),
  text: Color(0xFF35131F),
  mutedText: Color(0xFF7F4A5C),
  accent: Color(0xFFC2185B),
  accentAlt: Color(0xFFF06292),
  border: Color(0x33C2185B),
);

const AppThemePalette _coffeePalette = AppThemePalette(
  background: Color(0xFFF7EFE7),
  surface: Color(0xFFE9D8C6),
  surfaceAlt: Color(0xFFD8BFA5),
  text: Color(0xFF2B1A10),
  mutedText: Color(0xFF74533D),
  accent: Color(0xFF6F4E37),
  accentAlt: Color(0xFFB08968),
  border: Color(0x336F4E37),
);

const AppThemePalette _materialLightPalette = AppThemePalette(
  background: Color(0xFFF8F9FF),
  surface: Color(0xFFE8DEF8),
  surfaceAlt: Color(0xFFD0BCFF),
  text: Color(0xFF1D1B20),
  mutedText: Color(0xFF625B71),
  accent: Color(0xFF6750A4),
  accentAlt: Color(0xFF7D5260),
  border: Color(0x3321005D),
);

const AppThemePalette _materialDarkPalette = AppThemePalette(
  background: Color(0xFF141218),
  surface: Color(0xFF211F26),
  surfaceAlt: Color(0xFF2B2930),
  text: Color(0xFFE6E0E9),
  mutedText: Color(0xFFCAC4D0),
  accent: Color(0xFFD0BCFF),
  accentAlt: Color(0xFFEFB8C8),
  border: Color(0x33E6E0E9),
);
