import 'package:flutter/material.dart';

import 'v3_container_utils.dart';

/// V3ButtonUtils - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ BUTTON-ИМА
/// Елиминише све ElevatedButton/TextButton/OutlinedButton дупликате!
class V3ButtonUtils {
  V3ButtonUtils._();

  // ─── STANDARD BUTTONS ─────────────────────────────────────────────────────

  /// Стандардни ElevatedButton са unified стилизовањем
  static Widget elevatedButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    Color? backgroundColor,
    Color? foregroundColor,
    bool isLoading = false,
    double? width,
    EdgeInsets? padding,
    BorderRadius? borderRadius,
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.bold,
  }) {
    final button = ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
      label: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: foregroundColor ?? Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? Colors.blue,
        foregroundColor: foregroundColor ?? Colors.white,
        padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
    );

    return width != null ? SizedBox(width: width, child: button) : button;
  }

  /// Primary action button (зелен)
  static Widget primaryButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    bool isLoading = false,
    double? width,
  }) {
    return elevatedButton(
      onPressed: onPressed,
      text: text,
      icon: icon,
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      isLoading: isLoading,
      width: width,
    );
  }

  /// Success action button (светло зелен)
  static Widget successButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    bool isLoading = false,
    double? width,
  }) {
    return elevatedButton(
      onPressed: onPressed,
      text: text,
      icon: icon,
      backgroundColor: Colors.lightGreen,
      foregroundColor: Colors.white,
      isLoading: isLoading,
      width: width,
    );
  }

  /// Warning action button (наранџаст)
  static Widget warningButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    bool isLoading = false,
    double? width,
  }) {
    return elevatedButton(
      onPressed: onPressed,
      text: text,
      icon: icon,
      backgroundColor: Colors.orange,
      foregroundColor: Colors.white,
      isLoading: isLoading,
      width: width,
    );
  }

  /// Danger action button (црвен)
  static Widget dangerButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    bool isLoading = false,
    double? width,
  }) {
    return elevatedButton(
      onPressed: onPressed,
      text: text,
      icon: icon,
      backgroundColor: Colors.red,
      foregroundColor: Colors.white,
      isLoading: isLoading,
      width: width,
    );
  }

  /// Amber action button (жут)
  static Widget amberButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    bool isLoading = false,
    double? width,
  }) {
    return elevatedButton(
      onPressed: onPressed,
      text: text,
      icon: icon,
      backgroundColor: Colors.amber,
      foregroundColor: Colors.black,
      isLoading: isLoading,
      width: width,
    );
  }

  // ─── OUTLINED BUTTONS ─────────────────────────────────────────────────────

  /// Стандардни OutlinedButton са unified стилизовањем
  static Widget outlinedButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    Color? borderColor,
    Color? foregroundColor,
    bool isLoading = false,
    double? width,
    EdgeInsets? padding,
    BorderRadius? borderRadius,
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    final button = OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foregroundColor ?? Colors.blue,
              ),
            )
          : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
      label: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: foregroundColor ?? Colors.blue,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: foregroundColor ?? Colors.blue,
        side: BorderSide(color: borderColor ?? Colors.blue),
        padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(12),
        ),
      ),
    );

    return width != null ? SizedBox(width: width, child: button) : button;
  }

  /// Cancel/Secondary outlined button (сив)
  static Widget cancelButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    bool isLoading = false,
    double? width,
  }) {
    return outlinedButton(
      onPressed: onPressed,
      text: text,
      icon: icon,
      borderColor: Colors.grey,
      foregroundColor: Colors.grey,
      isLoading: isLoading,
      width: width,
    );
  }

  // ─── TEXT BUTTONS ─────────────────────────────────────────────────────────

  /// Стандардни TextButton са unified стилизовањем
  static Widget textButton({
    required VoidCallback? onPressed,
    required String text,
    IconData? icon,
    Color? foregroundColor,
    bool isLoading = false,
    double? width,
    EdgeInsets? padding,
    BorderRadius? borderRadius,
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    final button = TextButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foregroundColor ?? Colors.blue,
              ),
            )
          : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
      label: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: foregroundColor ?? Colors.blue,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor ?? Colors.blue,
        padding: padding ?? const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(12),
        ),
      ),
    );

    return width != null ? SizedBox(width: width, child: button) : button;
  }

  // ─── SPECIALIZED BUTTONS ──────────────────────────────────────────────────

  /// Компактни action button за листе
  static Widget compactButton({
    required VoidCallback? onPressed,
    required String text,
    required IconData icon,
    required Color color,
    double height = 32,
  }) {
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.08)],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 13, color: color),
          label: Text(
            text,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
            overflow: TextOverflow.ellipsis,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          ),
        ),
      ),
    );
  }

  /// Glass morphism button за навигацију
  static Widget glassButton({
    required VoidCallback? onPressed,
    required Widget child,
    Color? backgroundColor,
    Color? borderColor,
    double? width,
    double? height,
    EdgeInsets? padding,
    BorderRadius? borderRadius,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: InkWell(
        onTap: onPressed,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        child: V3ContainerUtils.styledContainer(
          padding: padding ?? const EdgeInsets.all(12),
          backgroundColor: backgroundColor ?? Colors.white.withValues(alpha: 0.15),
          borderRadius: borderRadius ?? BorderRadius.circular(12),
          border: Border.all(
            color: borderColor ?? Colors.white.withValues(alpha: 0.6),
            width: 1,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
