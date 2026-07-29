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

  // Stitch "Digital Librarian" palette.
  static const Color _lightPrimary = Color(0xFF005AC2);
  static const Color _darkPrimary = Color(0xFFADC6FF);

  static const Color _lightBackground = Color(0xFFF4F7FF);
  static const Color _darkBackground = Color(0xFF020617);

  // --- Gradients ---
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF4D8EFF),
      Color(0xFF00A572),
    ],
  );

  static const LinearGradient neonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF4D8EFF),
      Color(0xFF4EDEA3),
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
    final surface = isDark ? const Color(0xFF0B1326) : const Color(0xFFFFFFFF);
    final surfaceContainer =
        isDark ? const Color(0xFF171F33) : const Color(0xFFE9EEFA);
    final menuSurface =
        isDark ? const Color(0xFF131B2E) : const Color(0xFFFFFFFF);

    final colorScheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: primary,
      primary: primary,
      secondary: isDark ? const Color(0xFF4EDEA3) : const Color(0xFF006C49),
      tertiary: isDark ? const Color(0xFFD0BCFF) : const Color(0xFF6E3FD0),
      surface: surface,
    ).copyWith(
      surfaceContainer: surfaceContainer,
      surfaceContainerLowest:
          isDark ? const Color(0xFF060E20) : const Color(0xFFFFFFFF),
      surfaceContainerLow:
          isDark ? const Color(0xFF131B2E) : const Color(0xFFF0F3FB),
      surfaceContainerHigh:
          isDark ? const Color(0xFF222A3D) : const Color(0xFFE2E7F2),
      surfaceContainerHighest:
          isDark ? const Color(0xFF2D3449) : const Color(0xFFD9DFEC),
      onSurface: isDark ? const Color(0xFFDAE2FD) : const Color(0xFF101828),
      onSurfaceVariant:
          isDark ? const Color(0xFFC2C6D6) : const Color(0xFF4C566A),
      outline: isDark ? const Color(0xFF8C909F) : const Color(0xFF70798C),
      outlineVariant:
          isDark ? const Color(0xFF424754) : const Color(0xFFD2D8E4),
      shadow: isDark
          ? Colors.black.withValues(alpha: 0.5)
          : Colors.black.withValues(alpha: 0.1),
    );
    final menuBorderColor = colorScheme.outline.withValues(alpha: 0.45);
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: menuBorderColor),
    );

    final baseTextTheme =
        GoogleFonts.interTextTheme().apply(fontFamilyFallback: _fallbackFonts);
    TextStyle withFallback(TextStyle? style) =>
        style?.copyWith(fontFamilyFallback: _fallbackFonts) ??
        const TextStyle(fontFamilyFallback: _fallbackFonts);

    final textTheme = baseTextTheme.copyWith(
      displayLarge: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: -1.0,
          color: colorScheme.onSurface)),
      displayMedium: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
          color: colorScheme.onSurface)),
      displaySmall: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
          color: colorScheme.onSurface)),
      headlineLarge: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: colorScheme.onSurface)),
      headlineMedium: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
      headlineSmall: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.35,
          color: colorScheme.onSurface)),
      titleLarge: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.15,
          color: colorScheme.onSurface)),
      titleMedium: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
      titleSmall: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600, color: colorScheme.onSurface)),
      bodyLarge: withFallback(
          GoogleFonts.inter(height: 1.6, color: colorScheme.onSurface)),
      bodyMedium: withFallback(
          GoogleFonts.inter(height: 1.5, color: colorScheme.onSurface)),
      bodySmall: withFallback(
          GoogleFonts.inter(height: 1.45, color: colorScheme.onSurface)),
      labelMedium: withFallback(GoogleFonts.jetBrainsMono(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: colorScheme.onSurface)),
      labelSmall: withFallback(GoogleFonts.jetBrainsMono(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
          color: colorScheme.onSurfaceVariant)),
      labelLarge: withFallback(GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: colorScheme.onSurface)),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: background,
      canvasColor: menuSurface,

      // --- AppBar ---
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, // Transparent for glass effect
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
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
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isDark ? const Color(0xFF424754) : const Color(0xFFD2D8E4),
            width: 1,
          ),
        ),
      ),

      // --- Inputs ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF171F33) : const Color(0xFFE9EEFA),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),

      // --- Buttons ---
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
          elevation: 0,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
            ? const Color(0xFF060E20).withValues(alpha: 0.96)
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
      popupMenuTheme: PopupMenuThemeData(
        color: menuSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
        elevation: 12,
        shape: menuShape,
        textStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
              colorScheme.shadow.withValues(alpha: 0.25)),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(menuShape),
          side: WidgetStatePropertyAll(BorderSide(color: menuBorderColor)),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
              colorScheme.shadow.withValues(alpha: 0.25)),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(menuShape),
          side: WidgetStatePropertyAll(BorderSide(color: menuBorderColor)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark ? const Color(0xFF111827) : Colors.white,
          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primary, width: 2),
          ),
        ),
      ),
    );
  }
}
