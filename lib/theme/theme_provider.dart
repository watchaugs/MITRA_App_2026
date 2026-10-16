import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. The Hard Drive Link (Allows main.dart to pass the memory in)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialized in main.dart');
});

// 2. Define your 5 new themes
enum MitraTheme {
  midnightSlate,
  deepForest,
  twilightPurple,
  warmCharcoal,
  abyssalBlue,
  // ── Light themes ─────────────────────────
  banyanGreen, // Option 3: mint white + emerald
  riverSky, // Option 5: ice white + cerulean blue
}

// 3. ✨ NEW: The Smart Theme Notifier (Replaces StateProvider)
class ThemeNotifier extends StateNotifier<MitraTheme> {
  final SharedPreferences _prefs;
  static const _themeKey = 'mitra_custom_theme_saved';

  // When the app boots, instantly load the saved theme
  ThemeNotifier(this._prefs) : super(_loadSavedTheme(_prefs));

  static MitraTheme _loadSavedTheme(SharedPreferences prefs) {
    final savedThemeName = prefs.getString(_themeKey);
    if (savedThemeName != null) {
      // Find the saved theme from the enum list
      final saved = MitraTheme.values.firstWhere(
        (theme) => theme.name == savedThemeName,
        orElse: () => MitraTheme.midnightSlate,
      );
      // A user who had picked a (now-hidden) light theme falls back to the
      // default dark theme so they are never stuck on an unreadable screen.
      return ThemeHelper.isLightTheme(saved) ? MitraTheme.midnightSlate : saved;
    }
    return MitraTheme.midnightSlate; // Default if nothing is saved
  }

  // ✨ NEW: The method that updates the UI AND saves to the hard drive!
  void setTheme(MitraTheme theme) {
    state = theme;
    _prefs.setString(_themeKey, theme.name);
  }
}

// 4. ✨ NEW: The upgraded Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, MitraTheme>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});

// 5. The Helper class (Untouched - your beautiful colors remain intact!)
class ThemeHelper {
  static List<Color> getBackgroundGradient(MitraTheme theme) {
    switch (theme) {
      case MitraTheme.midnightSlate:
        return [const Color(0xFF1E293B), const Color(0xFF0F172A)];
      case MitraTheme.deepForest:
        return [const Color(0xFF064E3B), const Color(0xFF022C22)];
      case MitraTheme.twilightPurple:
        return [const Color(0xFF312E81), const Color(0xFF1E1B4B)];
      case MitraTheme.warmCharcoal:
        return [const Color(0xFF292524), const Color(0xFF1C1917)];
      case MitraTheme.abyssalBlue:
        return [const Color(0xFF1E3A8A), const Color(0xFF172554)];
      // ── Light themes ───────────────────────────────────────
      case MitraTheme.banyanGreen:
        // Soft mint white fading to a slightly deeper mint
        return [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)];
      case MitraTheme.riverSky:
        // Cool ice white fading to a light sky tint
        return [const Color(0xFFF0F9FF), const Color(0xFFE0F2FE)];
    }
  }

  static Color getActiveHighlight(MitraTheme theme) {
    switch (theme) {
      case MitraTheme.midnightSlate:
        return const Color(0xFF22D3EE);
      case MitraTheme.deepForest:
        return const Color(0xFF34D399);
      case MitraTheme.twilightPurple:
        return const Color(0xFFFBBF24);
      case MitraTheme.warmCharcoal:
        return const Color(0xFFFCD34D);
      case MitraTheme.abyssalBlue:
        return const Color(0xFFFB923C);
      // ── Light themes ───────────────────────────────────────
      case MitraTheme.banyanGreen:
        return const Color(0xFF16A34A); // Emerald green
      case MitraTheme.riverSky:
        return const Color(0xFF0284C7); // Cerulean blue
    }
  }

  static String getThemeName(MitraTheme theme) {
    switch (theme) {
      case MitraTheme.midnightSlate:
        return "Midnight Slate";
      case MitraTheme.deepForest:
        return "Deep Forest";
      case MitraTheme.twilightPurple:
        return "Twilight Purple";
      case MitraTheme.warmCharcoal:
        return "Warm Charcoal";
      case MitraTheme.abyssalBlue:
        return "Abyssal Blue";
      // ── Light themes ───────────────────────────────────────
      case MitraTheme.banyanGreen:
        return "Banyan Green";
      case MitraTheme.riverSky:
        return "River Sky";
    }
  }

  static ThemeData getThemeData(MitraTheme theme) {
    final highlight = getActiveHighlight(theme);
    final bgColors = getBackgroundGradient(theme);
    final baseColor = bgColors.last;

    return ThemeData(
      // Light themes use Brightness.light so Flutter automatically
      // renders dark text, dark icons, and a dark status bar,
      // which is correct on a white/mint/ice background.
      brightness: isLightTheme(theme) ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: baseColor,
      primaryColor: highlight,
      colorScheme: isLightTheme(theme)
          ? ColorScheme.light(
              primary: highlight,
              surface: baseColor,
              onSurface: const Color(0xFF1A1A2E), // dark text on light bg
            )
          : ColorScheme.dark(
              primary: highlight,
              surface: baseColor,
            ),
      // Legible text everywhere: any Text without an explicit color
      // inherits dark ink on light themes, light ink on dark themes.
      textTheme: Typography.blackMountainView.apply(
        bodyColor: isLightTheme(theme) ? const Color(0xFF1A1A2E) : Colors.white,
        displayColor:
            isLightTheme(theme) ? const Color(0xFF1A1A2E) : Colors.white,
        fontFamily: 'Mukta',
      ),
      iconTheme: IconThemeData(
        color: isLightTheme(theme) ? const Color(0xFF1A1A2E) : Colors.white,
      ),
      fontFamily: 'Mukta',
    );
  }

  // Returns true for themes that use a light/white background.
  // Add new light themes to this list as you create them.
  static bool isLightTheme(MitraTheme theme) {
    return theme == MitraTheme.banyanGreen || theme == MitraTheme.riverSky;
  }

  // Themes offered in the picker. Light themes are hidden for launch because
  // many screens hardcode near-white text that is invisible on a light
  // background; dark themes render correctly. Re-add the light themes here once
  // the per-screen text colours are made theme-aware.
  static List<MitraTheme> get selectableThemes =>
      MitraTheme.values.where((t) => !isLightTheme(t)).toList();

  // ── Legible text colors, driven by theme brightness ──────
  // Use these everywhere instead of hardcoded Colors.white*.
  // On light themes (Banyan Green, River Sky) they return dark
  // ink; on dark themes they return light ink — always legible.
  static Color textPrimary(MitraTheme theme) =>
      isLightTheme(theme) ? const Color(0xFF1A1A2E) : Colors.white;

  static Color textSecondary(MitraTheme theme) => isLightTheme(theme)
      ? const Color(0xFF1A1A2E).withValues(alpha: 0.70)
      : Colors.white70;

  static Color textMuted(MitraTheme theme) => isLightTheme(theme)
      ? const Color(0xFF1A1A2E).withValues(alpha: 0.45)
      : Colors.white38;

  // ── Context-based helpers ────────────────────────────────
  static bool ctxIsLight(BuildContext c) =>
      Theme.of(c).brightness == Brightness.light;

  static Color ctxTextPrimary(BuildContext c) =>
      ctxIsLight(c) ? const Color(0xFF1A1A2E) : Colors.white;

  static Color ctxTextSecondary(BuildContext c) => ctxIsLight(c)
      ? const Color(0xFF1A1A2E).withValues(alpha: 0.70)
      : Colors.white70;

  static Color ctxTextMuted(BuildContext c) => ctxIsLight(c)
      ? const Color(0xFF1A1A2E).withValues(alpha: 0.45)
      : Colors.white38;

  static Color ctxGlassFill(BuildContext c,
          {double dark = 0.08, double light = 0.05}) =>
      ctxIsLight(c)
          ? Colors.black.withValues(alpha: light)
          : Colors.white.withValues(alpha: dark);

  static Color ctxGlassBorder(BuildContext c,
          {double dark = 0.15, double light = 0.10}) =>
      ctxIsLight(c)
          ? Colors.black.withValues(alpha: light)
          : Colors.white.withValues(alpha: dark);
}
