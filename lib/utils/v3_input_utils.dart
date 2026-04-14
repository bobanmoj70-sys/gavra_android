import 'package:flutter/material.dart';
import 'package:gavra_android/utils/v3_phone_utils.dart';

/// V3InputUtils - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ INPUT FIELD-ОВИМА
/// Елиминише све TextField/TextFormField дупликате!
class V3InputUtils {
  V3InputUtils._();

  // ─── СТАНДАРДНИ INPUT FIELD-ОВИ ─────────────────────────────────────────

  /// Стандардни TextField са unified стилизовањем
  static Widget textField({
    Key? fieldKey,
    required TextEditingController controller,
    required String label,
    IconData? icon,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool isDense = false,
    int? maxLines,
    String? suffixText,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
    Color? fillColor,
    Color? borderColor,
    Color? focusedBorderColor,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final resolvedFill = fillColor ??
            (isDark
                ? Colors.white.withValues(alpha: 0.10)
                : cs.surfaceContainerHighest);
        final resolvedBorder = borderColor ??
            (isDark ? Colors.white30 : cs.outline.withValues(alpha: 0.6));
        final resolvedFocused = focusedBorderColor ?? cs.primary;
        final textColor = cs.onSurface;
        final labelColor = cs.onSurface.withValues(alpha: 0.78);
        final hintColor = cs.onSurface.withValues(alpha: 0.45);
        final iconColor = isDark ? Colors.amber : cs.primary;

        return TextField(
          key: fieldKey,
          controller: controller,
          style: TextStyle(color: textColor),
          cursorColor: cs.primary,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: obscureText ? 1 : maxLines,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: labelColor),
            hintText: hint,
            hintStyle: TextStyle(color: hintColor),
            prefixIcon: icon != null ? Icon(icon, color: iconColor) : null,
            suffixIcon: suffixIcon,
            suffixText: suffixText,
            suffixStyle: TextStyle(color: labelColor),
            filled: true,
            fillColor: resolvedFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: resolvedBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: resolvedFocused),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            isDense: isDense,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isDense ? 12 : 16,
            ),
          ),
        );
      },
    );
  }

  /// TextFormField са валидацијом и unified стилизовањем
  static Widget formField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool isDense = false,
    int? maxLines,
    String? suffixText,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    Color? fillColor,
    Color? borderColor,
    Color? focusedBorderColor,
  }) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final resolvedFill = fillColor ??
            (isDark
                ? Colors.white.withValues(alpha: 0.10)
                : cs.surfaceContainerHighest);
        final resolvedBorder = borderColor ??
            (isDark ? Colors.white30 : cs.outline.withValues(alpha: 0.6));
        final resolvedFocused = focusedBorderColor ?? cs.primary;
        final textColor = cs.onSurface;
        final labelColor = cs.onSurface.withValues(alpha: 0.78);
        final hintColor = cs.onSurface.withValues(alpha: 0.45);
        final iconColor = isDark ? Colors.amber : cs.primary;

        return TextFormField(
          controller: controller,
          style: TextStyle(color: textColor),
          cursorColor: cs.primary,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: obscureText ? 1 : maxLines,
          onFieldSubmitted: onSubmitted,
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: labelColor),
            hintText: hint,
            hintStyle: TextStyle(color: hintColor),
            prefixIcon: icon != null ? Icon(icon, color: iconColor) : null,
            suffixIcon: suffixIcon,
            suffixText: suffixText,
            suffixStyle: TextStyle(color: labelColor),
            filled: true,
            fillColor: resolvedFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: resolvedBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: resolvedFocused),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            isDense: isDense,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isDense ? 12 : 16,
            ),
          ),
        );
      },
    );
  }

  // ─── СПЕЦИЈАЛИЗОВАНИ INPUT FIELD-ОВИ ────────────────────────────────────

  /// Телефон input field са валидацијом
  static Widget phoneField({
    required TextEditingController controller,
    String label = 'Број телефона',
    String? hint,
    bool isRequired = true,
  }) {
    return formField(
      controller: controller,
      label: label,
      icon: Icons.phone,
      hint: hint ?? '06x xxx xxxx',
      keyboardType: TextInputType.phone,
      validator: (v) => phoneValidator(v, isRequired: isRequired),
    );
  }

  /// Number input field
  static Widget numberField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? suffixText,
    String? Function(String?)? validator,
    bool isDense = false,
  }) {
    return formField(
      controller: controller,
      label: label,
      icon: Icons.numbers,
      hint: hint,
      keyboardType: TextInputType.number,
      suffixText: suffixText,
      validator: validator,
      isDense: isDense,
    );
  }

  /// Multiline text field
  static Widget multilineField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 4,
    String? Function(String?)? validator,
  }) {
    return formField(
      controller: controller,
      label: label,
      icon: Icons.text_fields,
      hint: hint,
      maxLines: maxLines,
      validator: validator,
    );
  }

  // ─── ВАЛИДАТОРИ ─────────────────────────────────────────────────────────

  /// Стандардни required валидатор
  static String? requiredValidator(String? value,
      [String message = 'Ово поље је обавезно']) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  /// Телефон валидатор
  static String? phoneValidator(String? value, {bool isRequired = true}) {
    final normalized = value?.trim() ?? '';
    if (isRequired && normalized.isEmpty) {
      return 'Унесите број телефона';
    }
    if (normalized.isNotEmpty) {
      final digitsOnly = normalized.replaceAll(RegExp(r'\D'), '');
      if (digitsOnly.length < 8 || digitsOnly.length > 15) {
        return 'Неисправан број телефона';
      }
      if ((normalized.startsWith('+') ||
              normalized.startsWith('0') ||
              normalized.startsWith('381')) &&
          !V3PhoneUtils.isValid(normalized)) {
        return 'Неисправан број телефона';
      }
    }
    return null;
  }
}
