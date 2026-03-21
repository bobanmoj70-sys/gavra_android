import 'package:flutter/material.dart';

/// V3InputUtils - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ INPUT FIELD-ОВИМА
/// Елиминише све TextField/TextFormField дупликате!
class V3InputUtils {
  V3InputUtils._();

  // ─── СТАНДАРДНИ INPUT FIELD-ОВИ ─────────────────────────────────────────

  /// Стандардни TextField са unified стилизовањем
  static Widget textField({
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
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        prefixIcon: icon != null ? Icon(icon, color: Colors.amber) : null,
        suffixIcon: suffixIcon,
        suffixText: suffixText,
        filled: true,
        fillColor: fillColor ?? Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor ?? Colors.white30),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusedBorderColor ?? Colors.amber),
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
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        prefixIcon: icon != null ? Icon(icon, color: Colors.amber) : null,
        suffixIcon: suffixIcon,
        suffixText: suffixText,
        filled: true,
        fillColor: fillColor ?? Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor ?? Colors.white30),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusedBorderColor ?? Colors.amber),
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
  }

  // ─── СПЕЦИЈАЛИЗОВАНИ INPUT FIELD-ОВИ ────────────────────────────────────

  /// Email input field са валидацијом
  static Widget emailField({
    required TextEditingController controller,
    String label = 'Email адреса',
    String? hint,
    bool isRequired = true,
  }) {
    return formField(
      controller: controller,
      label: label,
      icon: Icons.email,
      hint: hint,
      keyboardType: TextInputType.emailAddress,
      validator: (v) {
        if (isRequired && (v == null || v.trim().isEmpty)) {
          return 'Унесите email';
        }
        if (v != null && v.isNotEmpty && (!v.contains('@') || !v.contains('.'))) {
          return 'Неисправан email формат';
        }
        return null;
      },
    );
  }

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
      validator: (v) {
        if (isRequired && (v == null || v.trim().isEmpty)) {
          return 'Унесите број телефона';
        }
        return null;
      },
    );
  }

  /// Шифра input field са toggle visibility
  static Widget passwordField({
    required TextEditingController controller,
    required bool isVisible,
    required VoidCallback onToggleVisibility,
    String label = 'Шифра',
    String? hint,
    String? Function(String?)? validator,
  }) {
    return formField(
      controller: controller,
      label: label,
      icon: Icons.lock,
      hint: hint,
      obscureText: !isVisible,
      suffixIcon: IconButton(
        icon: Icon(
          isVisible ? Icons.visibility_off : Icons.visibility,
          color: Colors.white60,
        ),
        onPressed: onToggleVisibility,
      ),
      validator: validator,
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

  /// PIN input field са специјалним стилизовањем
  static Widget pinField({
    required TextEditingController controller,
    String label = 'PIN код',
    String? hint = '• • • •',
    int maxLength = 4,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        letterSpacing: 8,
        fontWeight: FontWeight.bold,
      ),
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: maxLength,
      obscureText: true,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 8),
        counterText: '', // Сакриј counter
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.amber),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
      ),
    );
  }

  // ─── ВАЛИДАТОРИ ─────────────────────────────────────────────────────────

  /// Стандардни required валидатор
  static String? requiredValidator(String? value, [String message = 'Ово поље је обавезно']) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  /// Email валидатор
  static String? emailValidator(String? value, {bool isRequired = true}) {
    if (isRequired && (value == null || value.trim().isEmpty)) {
      return 'Унесите email адресу';
    }
    if (value != null && value.isNotEmpty) {
      if (!value.contains('@') || !value.contains('.')) {
        return 'Неисправан email формат';
      }
    }
    return null;
  }

  /// Телефон валидатор
  static String? phoneValidator(String? value, {bool isRequired = true}) {
    if (isRequired && (value == null || value.trim().isEmpty)) {
      return 'Унесите број телефона';
    }
    return null;
  }

  /// Шифра валидатор
  static String? passwordValidator(String? value, {int minLength = 4}) {
    if (value == null || value.isEmpty) {
      return 'Унесите шифру';
    }
    if (value.length < minLength) {
      return 'Шифра мора имати минимум $minLength карактера';
    }
    return null;
  }

  /// Потврда шифре валидатор
  static String? confirmPasswordValidator(String? value, String originalPassword) {
    if (value == null || value.isEmpty) {
      return 'Потврдите шифру';
    }
    if (value != originalPassword) {
      return 'Шифре се не покпапају';
    }
    return null;
  }
}
