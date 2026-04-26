import 'package:flutter/material.dart';

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
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
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
        padding:
            padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
        padding:
            padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(12),
        ),
      ),
    );

    return width != null ? SizedBox(width: width, child: button) : button;
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
        padding:
            padding ?? const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(12),
        ),
      ),
    );

    return width != null ? SizedBox(width: width, child: button) : button;
  }

}
