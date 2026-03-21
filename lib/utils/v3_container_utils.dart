import 'package:flutter/material.dart';

/// V3ContainerUtils - Centralized container management
/// Eliminira sve Container duplikate sa konzistentnim stilizovanjem
class V3ContainerUtils {
  /// Basic styled container sa padding
  static Widget styledContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    double? width,
    double? height,
    BorderRadiusGeometry? borderRadius,
    BoxBorder? border,
    List<BoxShadow>? boxShadow,
    AlignmentGeometry? alignment,
    DecorationImage? backgroundImage,
    Gradient? gradient,
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      margin: margin,
      alignment: alignment,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius ?? BorderRadius.circular(8.0),
        border: border,
        boxShadow: boxShadow,
        image: backgroundImage,
        gradient: gradient,
      ),
      child: child,
    );
  }

  /// Card-like container sa elevation effect
  static Widget cardContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    double? width,
    double? height,
    double elevation = 2.0,
    double borderRadius = 12.0,
    AlignmentGeometry? alignment,
    BoxBorder? border,
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      alignment: alignment,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: elevation * 2,
            spreadRadius: elevation / 2,
            offset: Offset(0, elevation),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Rounded container sa border
  static Widget roundedContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    Color? borderColor,
    double? width,
    double? height,
    double borderRadius = 8.0,
    double borderWidth = 1.0,
    AlignmentGeometry? alignment,
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(12.0),
      margin: margin,
      alignment: alignment,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor != null ? Border.all(color: borderColor, width: borderWidth) : null,
      ),
      child: child,
    );
  }

  /// Gradient container
  static Widget gradientContainer({
    required Widget child,
    required Gradient gradient,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    BorderRadiusGeometry? borderRadius,
    AlignmentGeometry? alignment,
    BoxBorder? border,
    List<BoxShadow>? boxShadow,
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      margin: margin,
      alignment: alignment,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: borderRadius ?? BorderRadius.circular(8.0),
        border: border,
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }

  /// Background container za full screen
  static Widget backgroundContainer({
    required Widget child,
    Color? backgroundColor,
    DecorationImage? backgroundImage,
    Gradient? gradient,
    EdgeInsetsGeometry? padding,
    AlignmentGeometry? alignment,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: backgroundColor,
        image: backgroundImage,
        gradient: gradient,
      ),
      child: child,
    );
  }

  /// Badge container (enhanced version)
  static Widget badgeContainer({
    required Widget child,
    Color? backgroundColor,
    Color? borderColor,
    EdgeInsetsGeometry? padding,
    double borderRadius = 20.0,
    double? borderWidth,
    BoxBorder? border,
    BorderRadiusGeometry? borderRadiusGeometry,
  }) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.blue,
        borderRadius: borderRadiusGeometry ?? BorderRadius.circular(borderRadius),
        border: border ??
            (borderColor != null && borderWidth != null ? Border.all(color: borderColor, width: borderWidth) : null),
      ),
      child: child,
    );
  }

  /// Icon container (enhanced version)
  static Widget iconContainer({
    Widget? icon,
    Widget? child,
    Color? backgroundColor,
    double? size,
    double? width,
    double? height,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double borderRadius = 8.0,
    BorderRadiusGeometry? borderRadiusGeometry,
    Color? borderColor,
    double? borderWidth,
    BoxBorder? border,
    List<BoxShadow>? boxShadow,
    AlignmentGeometry? alignment,
  }) {
    return Container(
      width: width ?? size,
      height: height ?? size,
      padding: padding ?? const EdgeInsets.all(8.0),
      margin: margin,
      alignment: alignment,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadiusGeometry ?? BorderRadius.circular(borderRadius),
        border: border ??
            (borderColor != null && borderWidth != null ? Border.all(color: borderColor, width: borderWidth) : null),
        boxShadow: boxShadow,
      ),
      child: child ?? icon,
    );
  }

  /// Section container za organizaciju sadržaja
  static Widget sectionContainer({
    required Widget child,
    String? title,
    TextStyle? titleStyle,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? backgroundColor,
    double borderRadius = 8.0,
    Color? borderColor,
  }) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 8.0),
      padding: padding ?? const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey[50],
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: title != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: titleStyle ??
                      const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12.0),
                child,
              ],
            )
          : child,
    );
  }

  /// Dismissible background container
  static Widget dismissibleBackground({
    required IconData icon,
    required Color backgroundColor,
    AlignmentGeometry alignment = Alignment.centerLeft,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      alignment: alignment,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20.0),
      color: backgroundColor,
      child: Icon(
        icon,
        color: Colors.white,
        size: 32.0,
      ),
    );
  }

  /// Loading overlay container
  static Widget loadingOverlay({
    required Widget child,
    bool isLoading = false,
    Color? loadingColor,
    String? loadingText,
  }) {
    return Container(
      child: Stack(
        children: [
          child,
          if (isLoading)
            Container(
              color: (loadingColor ?? Colors.black).withOpacity(0.3),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    if (loadingText != null) ...[
                      const SizedBox(height: 16.0),
                      Text(
                        loadingText,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Common gradient definitions
  static const Gradient blueGradient = LinearGradient(
    colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient greenGradient = LinearGradient(
    colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient redGradient = LinearGradient(
    colors: [Color(0xFFf44336), Color(0xFFd32f2f)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient orangeGradient = LinearGradient(
    colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
