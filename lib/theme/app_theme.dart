import 'package:flutter/material.dart';

/// Design tokens for the rebuilt UI. Grounded in Konsept 3 (the
/// competitor/market-research-informed concept the user picked as the
/// visual direction for the rebuild) — see Acrodix app #5, PM sentez #6.
class AppColors {
  AppColors._();

  static const Color night = Color(0xFF14101F);
  static const Color night2 = Color(0xFF1E1830);
  static const Color violet = Color(0xFF7C3AED);
  static const Color violetDeep = Color(0xFF5B21B6);
  static const Color coral = Color(0xFFFF5A46);
  static const Color coralDeep = Color(0xFFC93A2C);
  static const Color yellow = Color(0xFFFFC93C);
  static const Color mint = Color(0xFF33D6A6);
  static const Color cloud = Color(0xFFF7F3FF);
  static const Color mist = Color(0x99F7F3FF); // rgba(247,243,255,0.6)
  static const Color mistDim = Color(0x61F7F3FF); // rgba(247,243,255,0.38)

  static const List<Color> categoryPalette = [
    violet,
    coral,
    yellow,
    mint,
  ];
}

class AppRadii {
  AppRadii._();
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 26;
  static const double pill = 999;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.violet,
        secondary: AppColors.coral,
        tertiary: AppColors.yellow,
        surface: AppColors.night2,
        error: AppColors.coral,
      ),
      scaffoldBackgroundColor: AppColors.night,
      fontFamily: 'SF Pro Rounded',
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.cloud,
        displayColor: AppColors.cloud,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.night,
        foregroundColor: AppColors.cloud,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.cloud,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.night2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.yellow,
          foregroundColor: const Color(0xFF3B2400),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.night2,
        contentTextStyle: const TextStyle(color: AppColors.cloud),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.violet
              : AppColors.mist,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.violet.withValues(alpha: 0.4)
              : AppColors.night2,
        ),
      ),
    );
  }

  /// Gradient used for "side A" of a duel (violet).
  static const LinearGradient sideAGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.violet, AppColors.violetDeep],
  );

  /// Gradient used for "side B" of a duel (coral).
  static const LinearGradient sideBGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.coral, AppColors.coralDeep],
  );

  static LinearGradient categoryGradient(int index) {
    switch (index % 4) {
      case 0:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        );
      case 1:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B57), Color(0xFFD6402F)],
        );
      case 2:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD766), Color(0xFFE8A93A)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3DE0B0), Color(0xFF1FA97F)],
        );
    }
  }

  static Color categoryForeground(int index) =>
      index % 4 == 2 ? const Color(0xFF3B2400) : Colors.white;
}
