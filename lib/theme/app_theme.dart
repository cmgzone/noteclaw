import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get light => _baseTheme(Brightness.light);
  static ThemeData get dark => _baseTheme(Brightness.dark);

  static const List<String> _fallbackFonts = [
    'Noto Sans',
    'Noto Sans SC',
    'Noto Sans JP',
    'Arial Unicode MS',
    'sans-serif',
  ];

  // --- Premium Colors ---
  static const Color _lightPrimary = Color(0xFF6366F1); // Indigo 500
  static const Color _darkPrimary = Color(0xFF818CF8); // Indigo 400

  static const Color _lightBackground = Color(0xFFF8FAFC); // Slate 50
  static const Color _darkBackground =
      Color(0xFF020617); // Slate 950 (Deep Void)

  // --- Gradients ---
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF6366F1), // Indigo
      Color(0xFF8B5CF6), // Violet
      Color(0xFFEC4899), // Pink
    ],
  );

  static const LinearGradient neonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF22D3EE), // Cyan
      Color(0xFF818CF8), // Indigo
    ],
  );

  // --- Glass Effects ---
  static Color get glassColorLight => Colors.white.withValues(alpha: 0.7);
  static Color get glassColorDark =>
      const Color(0xFF0F172A).withValues(alpha: 0.6);
  static const double glassBlur = 10.0;

  static ThemeData _baseTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Core colors
    final primary = isDark ? _darkPrimary : _lightPrimary;
    final background = isDark ? _darkBackground : _lightBackground;

    // Surfaces (Cards, Bottom Sheets)
    // Dark mode uses deep slate with slight transparency for glass effects
    final surface = isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);
    final surfaceContainer =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    final colorScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: primary,
      primary: primary,
      secondary: isDark
          ? const Color(0xFF22D3EE)
          : const Color(0xFF0EA5E9), // Cyan accent
      tertiary: const Color(0xFFEC4899), // Pink
      surface: surface,
    ).copyWith(
      // Custom overrides for premium feel
      surfaceContainer: surfaceContainer,
      outline: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      outlineVariant:
          isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      shadow: isDark
          ? Colors.black.withValues(alpha: 0.5)
          : Colors.black.withValues(alpha: 0.1),
    );

    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme()
        .apply(fontFamilyFallback: _fallbackFonts);
    TextStyle withFallback(TextStyle? style) =>
        style?.copyWith(fontFamilyFallback: _fallbackFonts) ??
        const TextStyle(fontFamilyFallback: _fallbackFonts);

    final textTheme = baseTextTheme.copyWith(
      displayLarge: withFallback(GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          letterSpacing: -1.0,
          color: colorScheme.onSurface)),
      headlineLarge: withFallback(GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: colorScheme.onSurface)),
      headlineMedium: withFallback(GoogleFonts.outfit(
          fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
      titleLarge: withFallback(GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: colorScheme.onSurface)),
      titleMedium: withFallback(GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
      titleSmall: withFallback(GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
      bodyLarge: withFallback(GoogleFonts.plusJakartaSans(
          height: 1.6, color: colorScheme.onSurface)),
      bodyMedium: withFallback(GoogleFonts.plusJakartaSans(
          height: 1.5, color: colorScheme.onSurface)),
      bodySmall: withFallback(GoogleFonts.plusJakartaSans(
          height: 1.45, color: colorScheme.onSurface)),
      labelMedium: withFallback(GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: colorScheme.onSurface)),
      labelSmall: withFallback(GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: colorScheme.onSurfaceVariant)),
      labelLarge: withFallback(GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: colorScheme.onSurface)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: background,

      // --- AppBar ---
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, // Transparent for glass effect
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      // --- Cards (Glass Style) ---
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        // Semi-transparent color
        color: isDark
            ? const Color(0xFF1E293B).withValues(alpha: 0.5)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), // Softer corners
          side: BorderSide(
            color: isDark
                ? const Color(0xFF334155).withValues(alpha: 0.5)
                : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),

      // --- Inputs ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.5)
            : const Color(0xFFF1F5F9),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),

      // --- Buttons ---
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
          elevation: isDark ? 0 : 2,
          shadowColor: primary.withValues(alpha: 0.4),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: colorScheme.surfaceContainer,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          side: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
        ),
      ),

      // --- Navigation Bar ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.8)
            : Colors.white,
        indicatorColor: primary.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),

      // --- Other ---
      dividerTheme: DividerThemeData(
        color: colorScheme.outline.withValues(alpha: 0.2),
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.9)
            : Colors.white,
        modalBackgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
    );
  }
}
