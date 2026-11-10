import 'dart:ui';
import 'package:flutter/material.dart';

/// iPhone 15 Pro / iOS 27 Liquid Glass Design System
class LiquidGlassTheme {
  // Theme Palette - True Optical Translucency
  static const Color bgLight = Color(0xFFF6F7FB);
  static const Color surfaceLight = Color(0xFFEEF0F7);
  static const Color glassFillLight = Color(0x66FFFFFF); // ~40% translucent frosted white
  static const Color glassBorderLight = Color(0x45FFFFFF);
  static const Color activePillLight = Color(0x28007AFF);

  static const Color bgDark = Color(0xFF090810);
  static const Color surfaceDark = Color(0xFF141320);
  static const Color glassFillDark = Color(0x22FFFFFF); // ~13% white tint over deep obsidian
  static const Color glassBorderDark = Color(0x35FFFFFF);
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

  // Dimensions & Insets
  static const double dynamicIslandTopInset = 54.0;
  static const double dockHeight = 68.0;
  static const double glassBlurSigma = 28.0;

  // Active theme brightness toggle state
  static bool isDarkMode = false;

  static Color get bg => isDarkMode ? bgDark : bgLight;
  static Color get surface => isDarkMode ? surfaceDark : surfaceLight;
  static Color get activePill => isDarkMode ? activePillDark : activePillLight;
  static Color get glassFill => isDarkMode ? glassFillDark : glassFillLight;
  static Color get glassBorder => isDarkMode ? glassBorderDark : glassBorderLight;

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

/// Ambient Light Field Background - Emits subtle chromatic diffraction orbs
/// behind frosted glass surfaces to simulate realistic Apple refraction
class LiquidGlassBackground extends StatelessWidget {
  final Widget child;

  const LiquidGlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    return Container(
      color: LiquidGlassTheme.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Aura Orb 1: Top-Right (Electric Sapphire / Cyan Glow)
          Positioned(
            top: -60,
            right: -60,
            child: IgnorePointer(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (isDark ? const Color(0xFF0A60FF) : const Color(0xFF007AFF))
                          .withValues(alpha: isDark ? 0.22 : 0.12),
                      (isDark ? const Color(0xFF00C6FF) : const Color(0xFF5AC8FA))
                          .withValues(alpha: isDark ? 0.08 : 0.04),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Aura Orb 2: Mid-Left (Violet / Amethyst Glow)
          Positioned(
            top: 250,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (isDark ? const Color(0xFF8B25E2) : const Color(0xFFAF52DE))
                          .withValues(alpha: isDark ? 0.18 : 0.09),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
          ),

          // Aura Orb 3: Bottom-Center (Emerald / Cellular Glow)
          Positioned(
            bottom: -50,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (isDark ? const Color(0xFF00E676) : const Color(0xFF34C759))
                          .withValues(alpha: isDark ? 0.14 : 0.07),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.8],
                  ),
                ),
              ),
            ),
          ),

          // Screen Content
          child,
        ],
      ),
    );
  }
}

/// GPU-Accelerated Diamond-Cut Glass Specular Gradient Rim Painter
class GlassBorderPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  final Gradient gradient;

  GlassBorderPainter({
    required this.radius,
    this.strokeWidth = 1.0,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant GlassBorderPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.strokeWidth != strokeWidth;
  }
}

/// GPU-Accelerated Diamond-Cut Glass Specular Gradient Rim Painter for Circular Lenses
class GlassCircleBorderPainter extends CustomPainter {
  final double strokeWidth;
  final Gradient gradient;

  GlassCircleBorderPainter({
    this.strokeWidth = 1.0,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant GlassCircleBorderPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth || oldDelegate.gradient != gradient;
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
    this.borderRadius = 22.0,
    this.color,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = LiquidGlassTheme.isDarkMode;

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.glassBlurSigma,
          sigmaY: LiquidGlassTheme.glassBlurSigma,
        ),
        child: CustomPaint(
          foregroundPainter: GlassBorderPainter(
            radius: borderRadius,
            strokeWidth: 0.8,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0x70FFFFFF),
                      const Color(0x30FFFFFF),
                      const Color(0x10FFFFFF),
                    ]
                  : [
                      const Color(0x95FFFFFF),
                      const Color(0x55FFFFFF),
                      const Color(0x20000000),
                    ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
          child: Container(
            width: width,
            height: height,
            padding: padding ?? const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: color ?? LiquidGlassTheme.glassFill,
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: isDark
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: child,
          ),
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
