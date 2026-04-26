import 'package:flutter/material.dart';

/// V3ContainerUtils - Centralized container management
/// Eliminira sve Container duplikate sa konzistentnim stilizovanjem
class V3ContainerUtils {
  V3ContainerUtils._();

  /// Responsive visina zasnovana na text scale faktoru
  static double responsiveHeight(
    BuildContext context,
    double base, {
    double maxScaleExtra = 0.7,
    double intensity = 0.35,
  }) {
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final extra = (textScaleFactor - 1.0).clamp(0.0, maxScaleExtra).toDouble();
    return base * (1 + (extra * intensity));
  }

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
    Clip clipBehavior = Clip.antiAlias, // Safe overflow protection
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      margin: margin,
      alignment: alignment,
      clipBehavior: clipBehavior,
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
    Clip clipBehavior = Clip.antiAlias, // Safe overflow protection
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      alignment: alignment,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
    Clip clipBehavior = Clip.antiAlias, // Safe overflow protection
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(12.0),
      margin: margin,
      alignment: alignment,
      clipBehavior: clipBehavior,
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
    Clip clipBehavior = Clip.antiAlias, // Safe overflow protection
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      margin: margin,
      alignment: alignment,
      clipBehavior: clipBehavior,
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
    Clip clipBehavior = Clip.antiAlias, // Safe overflow protection
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: padding,
      alignment: alignment,
      clipBehavior: clipBehavior,
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
    Clip clipBehavior = Clip.antiAlias, // Safe overflow protection
  }) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.blue,
        borderRadius: borderRadiusGeometry ?? BorderRadius.circular(borderRadius),
        border: border ?? (borderColor != null ? Border.all(color: borderColor, width: borderWidth ?? 1.0) : null),
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
    Clip clipBehavior = Clip.antiAlias, // Safe overflow protection
  }) {
    return Container(
      width: width ?? size,
      height: height ?? size,
      padding: padding ?? const EdgeInsets.all(8.0),
      margin: margin,
      alignment: alignment,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadiusGeometry ?? BorderRadius.circular(borderRadius),
        border: border ?? (borderColor != null ? Border.all(color: borderColor, width: borderWidth ?? 1.0) : null),
        boxShadow: boxShadow,
      ),
      child: child ?? icon,
    );
  }
}
