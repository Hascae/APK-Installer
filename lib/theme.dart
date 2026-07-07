import 'package:flutter/material.dart';

/// 品牌色票：深海軍藍 + 青→靛漸層（與應用圖示一致）。
class BrandColors {
  static const navy = Color(0xFF101430);
  static const navyCard = Color(0xFF1A2040);
  static const cyan = Color(0xFF22D3EE);
  static const indigo = Color(0xFF818CF8);
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);

  static const glyphGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [cyan, indigo],
  );
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.indigo,
    brightness: Brightness.dark,
  ).copyWith(
    primary: BrandColors.cyan,
    secondary: BrandColors.indigo,
    surface: BrandColors.navy,
  );
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: BrandColors.navy,
    cardColor: BrandColors.navyCard,
  );
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.indigo,
    brightness: Brightness.light,
  ).copyWith(
    primary: const Color(0xFF0891B2),
    secondary: const Color(0xFF6366F1),
  );
  return _base(scheme);
}

ThemeData _base(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.onSurface.withOpacity(0.08),
    ),
  );
}
