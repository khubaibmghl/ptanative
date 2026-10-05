import 'dart:ui';
import 'package:flutter/material.dart';

/// iPhone 15 Pro / iOS 27 Liquid Glass Design System
class LiquidGlassTheme {
  // Theme Palette
  static const Color bgLight = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF2F2F7);
  static const Color glassFillLight = Color(0xE8F8F9FB);
  static const Color glassBorderLight = Color(0x1F000000);
  static const Color activePillLight = Color(0xFFE5E5EA);

  static const Color bgDark = Color(0xFF0C0B14);
  static const Color surfaceDark = Color(0xFF1A1828);
  static const Color glassFillDark = Color(0x28FFFFFF);
  static const Color glassBorderDark = Color(0x2EFFFFFF);
  static const Color activePillDark = Color(0x35007AFF);

  // Status & Brand Colors
  static const Color iosBlue = Color(0xFF007AFF);
  static const Color accentBlue = Color(0xFF007AFF);
  static const Color gsmGreen = Color(0xFF34C759);
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color crimsonRed = Color(0xFFFF3B30);
  static const Color goldOtp = Color(0xFFFFD60A);
  static const Color dynamicPill = Color(0xFF16161E);

  // Default Typography Colors
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF6C6C70);
  static const Color textTertiary = Color(0xFF8E8E93);

  static const Color textPrimaryDark = Color(0xFFF5F5F7);
  static const Color textSecondaryDark = Color(0xFF8E8E93);

  // Glass default constants
  static const Color glassFill = Color(0xE8F8F9FB);
  static const Color glassBorder = Color(0x1F000000);

  // Dimensions & Insets
  static const double dynamicIslandTopInset = 54.0;
  static const double dockHeight = 64.0;
  static const double glassBlurSigma = 25.0;

  // Active theme brightness toggle state
  static bool isDarkMode = false;

  static Color get bg => isDarkMode ? bgDark : bgLight;
  static Color get surface => isDarkMode ? surfaceDark : surfaceLight;
  static Color get activePill => isDarkMode ? activePillDark : activePillLight;

  static ThemeData get lightThemeData {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgLight,
      primaryColor: iosBlue,
      canvasColor: surfaceLight,
      fontFamily: '.SF Pro Text',
      colorScheme: const ColorScheme.light(
        primary: iosBlue,
        secondary: gsmGreen,
        surface: surfaceLight,
        error: crimsonRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  static ThemeData get darkThemeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: iosBlue,
      canvasColor: surfaceDark,
      fontFamily: '.SF Pro Text',
      colorScheme: const ColorScheme.dark(
        primary: iosBlue,
        secondary: gsmGreen,
        surface: surfaceDark,
        error: crimsonRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimaryDark),
        titleTextStyle: TextStyle(
          color: textPrimaryDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  static ThemeData get themeData => isDarkMode ? darkThemeData : lightThemeData;
}

/// Frosted Liquid Glass Card with Specular Border & Backdrop Blur
class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 20.0,
    this.color,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlurSigma,
          sigmaY: LiquidGlassTheme.glassBlurSigma,
        ),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: color ?? LiquidGlassTheme.glassFill,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ??
                Border.all(
                  color: LiquidGlassTheme.glassBorder,
                  width: 0.5,
                ),
            boxShadow: LiquidGlassTheme.isDarkMode
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }

    return card;
  }
}
