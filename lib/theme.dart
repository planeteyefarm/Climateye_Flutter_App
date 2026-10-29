import 'package:flutter/material.dart';

/// Map-first night palette: midnight / deep-blue / slate-blue glass over the
/// map, a single teal accent and cool light text. Data colours (AQI bands,
/// chart series, methane ramps) live with their widgets and are
/// intentionally not themed.
class AppColors {
  // Surfaces.
  static const midnight = Color(0xFF0B1724);
  static const deepBlue = Color(0xFF14283A);
  static const slateBlue = Color(0xFF203D52);

  static const glassDeep = midnight;
  static const glassForest = deepBlue;
  static const glassTeal = slateBlue;

  /// Opaque fallback behind the map and on full-page screens.
  static const deepForest = midnight;

  // Accent.
  static const mint = Color(0xFF45D6C5);
  static const cyan = Color(0xFF7FE6DA);
  static const softMint = Color(0xFFD3E2EE);

  // Text.
  static const cloudWhite = Color(0xFFF4F7FB);
  static const white = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA8BACB);
  static const borderLight = Color(0xFFE2E8F0);

  // Roles.
  static const background = midnight;
  static const card = deepBlue;
  static const header = midnight;
  static const accent = mint;
  static const green = mint;

  /// Secondary text at 22%: hairline edges.
  static const border = Color(0x38A8BACB);

  static const textMuted = textSecondary;
  static const error = Color(0xFFEF4444);
}

class AppGradients {
  /// Primary actions: Mint → luminous mint.
  static const primary = LinearGradient(
    colors: [AppColors.mint, AppColors.cyan],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Nested section inside a glass panel: midnight at 45–30%.
  static const card = LinearGradient(
    colors: [Color(0x730B1724), Color(0x4D0B1724)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const header = LinearGradient(
    colors: [AppColors.glassDeep, AppColors.glassForest],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const nature = LinearGradient(
    colors: [AppColors.mint, AppColors.cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Full-page backdrop for screens without a map.
  static const page = LinearGradient(
    colors: [AppColors.glassForest, AppColors.glassDeep],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppDecorations {
  static const radius = 18.0;

  /// Card sitting on a glass panel or page: translucent sheen + fine border.
  static BoxDecoration card({double radius = AppDecorations.radius}) => BoxDecoration(
        gradient: AppGradients.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      );

  /// Floating glass surface over the map (pair with a BackdropFilter).
  static BoxDecoration glass({double radius = 20, double opacity = 0.72}) => BoxDecoration(
        color: AppColors.glassDeep.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      );
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.mint,
      onPrimary: AppColors.white,
      secondary: AppColors.softMint,
      surface: AppColors.card,
      onSurface: AppColors.cloudWhite,
      error: AppColors.error,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.cloudWhite,
      displayColor: AppColors.cloudWhite,
    ),
    iconTheme: const IconThemeData(color: AppColors.softMint),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.deepForest,
      foregroundColor: AppColors.cloudWhite,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDecorations.radius),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.card,
      contentTextStyle: TextStyle(color: AppColors.cloudWhite),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.card),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.deepForest),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.deepForest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.mint.withValues(alpha: 0.4)),
      ),
      textStyle: const TextStyle(color: AppColors.cloudWhite, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white.withValues(alpha: 0.06),
      labelStyle: const TextStyle(color: AppColors.textMuted),
      prefixIconColor: AppColors.textMuted,
      suffixIconColor: AppColors.textMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.mint, width: 1.4),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.mint,
        foregroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.cloudWhite,
        side: BorderSide(color: AppColors.mint.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.mint),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
  );
}
