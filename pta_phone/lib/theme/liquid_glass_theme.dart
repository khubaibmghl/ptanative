import 'dart:ui';
import 'package:flutter/material.dart';

/// iPhone 15 Pro Liquid Glass Design System
class LiquidGlassTheme {
  // Theme Palette
  static const Color bgDark = Color(0xFF08080C);
  static const Color surfaceDark = Color(0xFF121218);
  static const Color glassFill = Color(0x1FFFFFFF);
  static const Color glassFillDeep = Color(0x281A1A24);
  static const Color glassBorder = Color(0x2EFFFFFF);
  static const Color specularHighlight = Color(0x40FFFFFF);

  // Status & Brand Colors
  static const Color gsmGreen = Color(0xFF30D158);
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color crimsonRed = Color(0xFFFF453A);
  static const Color dynamicPill = Color(0xFF16161E);
  static const Color accentBlue = Color(0xFF0A84FF);
  static const Color goldOtp = Color(0xFFFFD60A);

  // Typography Colors
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF48484A);

  // Dimensions & Insets
  static const double dynamicIslandTopInset = 54.0;
  static const double dockHeight = 72.0;
  static const double glassBlurSigma = 24.0;

  // ThemeData
  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: accentBlue,
      canvasColor: surfaceDark,
      fontFamily: '.SF Pro Text',
      colorScheme: const ColorScheme.dark(
        primary: accentBlue,
        secondary: gsmGreen,
        surface: surfaceDark,
        error: crimsonRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
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
                  width: 0.75,
                ),
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
