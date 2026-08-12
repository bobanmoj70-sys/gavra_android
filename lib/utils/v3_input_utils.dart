import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gavra_android/utils/v3_phone_utils.dart';

/// Centralizovani input stil — ista bela/neutralna polja svuda (sve teme).
class V3InputStyle {
  const V3InputStyle._();

  static const Color fill = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFCBD5E1);
  static const Color focused = Color(0xFF2563EB);
  static const Color text = Color(0xFF0F172A);
  static const Color label = Color(0xFF64748B);
  static const Color hint = Color(0xFF94A3B8);
  static const Color icon = Color(0xFF475569);
  static const Color dropdownMenu = Colors.white;
  static const double radius = 12;
}

/// V3InputUtils — jedan izvor istine za TextField / TextFormField / dropdown / search.
class V3InputUtils {
  V3InputUtils._();

  static Future<void> pasteFromClipboardIntoController(TextEditingController controller) async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final pasteText = (clipboardData?.text ?? '').trim();
    if (pasteText.isEmpty) return;

    final value = controller.value;
    final selection = value.selection;

    if (!selection.isValid) {
      final merged = '${value.text}$pasteText';
      controller.value = value.copyWith(
        text: merged,
        selection: TextSelection.collapsed(offset: merged.length),
        composing: TextRange.empty,
      );
      return;
    }

    final start = math.max(0, math.min(selection.start, selection.end));
    final end = math.max(start, math.max(selection.start, selection.end));

    final merged = value.text.replaceRange(start, end, pasteText);
    final cursorOffset = start + pasteText.length;

    controller.value = value.copyWith(
      text: merged,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }

  static Widget? _buildSuffixActions({
    required TextEditingController controller,
    required Color iconColor,
    Widget? suffixIcon,
    bool showPaste = true,
    bool enabled = true,
  }) {
    final actions = <Widget>[
      if (suffixIcon != null) suffixIcon,
      if (showPaste)
        IconButton(
          tooltip: 'Nalepi',
          icon: Icon(Icons.content_paste_rounded, color: iconColor, size: 20),
          onPressed: enabled ? () => pasteFromClipboardIntoController(controller) : null,
        ),
    ];

    if (actions.isEmpty) return null;
    if (actions.length == 1) return actions.first;

    return SizedBox(
      width: actions.length * 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: actions,
      ),
    );
  }

  /// Standardni InputDecoration — uvek [V3InputStyle].
  static InputDecoration decoration({
    String? label,
    String? hint,
    IconData? icon,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? suffixText,
    bool isDense = false,
    Color? fillColor,
    Color? borderColor,
    Color? focusedBorderColor,
    Color? textColor,
    Color? iconColor,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final fill = fillColor ?? V3InputStyle.fill;
    final borderCol = borderColor ?? V3InputStyle.border;
    final focused = focusedBorderColor ?? V3InputStyle.focused;
    final labelCol = textColor != null ? textColor.withValues(alpha: 0.72) : V3InputStyle.label;
    final hintCol = textColor != null ? textColor.withValues(alpha: 0.45) : V3InputStyle.hint;
    final iconCol = iconColor ?? V3InputStyle.icon;
    final r = BorderRadius.circular(V3InputStyle.radius);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelCol),
      floatingLabelStyle: TextStyle(color: focused, fontWeight: FontWeight.w600),
      hintText: hint,
      hintStyle: TextStyle(color: hintCol),
      prefixIcon: prefixIcon ?? (icon != null ? Icon(icon, color: iconCol) : null),
      suffixIcon: suffixIcon,
      suffixText: suffixText,
      suffixStyle: TextStyle(color: labelCol),
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(borderRadius: r, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: borderCol)),
      focusedBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: BorderSide(color: focused, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: r,
        borderSide: const BorderSide(color: Colors.red),
      ),
      isDense: isDense,
      contentPadding: contentPadding ??
          EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isDense ? 12 : 16,
          ),
    );
  }

  static InputDecoration dropdownDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
    Color? prefixIconColor,
    bool isDense = true,
  }) {
    return decoration(
      label: label,
      icon: icon,
      suffixIcon: suffixIcon,
      isDense: isDense,
      iconColor: prefixIconColor ?? V3InputStyle.icon,
    );
  }

  static TextStyle get fieldTextStyle =>
      const TextStyle(color: V3InputStyle.text, fontWeight: FontWeight.w500);

  static Widget textField({
    Key? fieldKey,
    required TextEditingController controller,
    String? label,
    IconData? icon,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool isDense = false,
    bool enabled = true,
    bool showPaste = true,
    int? maxLines,
    String? suffixText,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    final resolvedFocused = V3InputStyle.focused;

    return TextField(
      key: fieldKey,
      controller: controller,
      enabled: enabled,
      style: fieldTextStyle,
      cursorColor: resolvedFocused,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: decoration(
        label: label,
        hint: hint,
        icon: icon,
        suffixText: suffixText,
        isDense: isDense,
        suffixIcon: _buildSuffixActions(
          controller: controller,
          iconColor: V3InputStyle.icon,
          suffixIcon: suffixIcon,
          showPaste: showPaste,
          enabled: enabled,
        ),
      ),
    );
  }

  static Widget formField({
    required TextEditingController controller,
    String? label,
    IconData? icon,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool isDense = false,
    bool enabled = true,
    bool showPaste = true,
    int? maxLines,
    String? suffixText,
    ValueChanged<String>? onSubmitted,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      style: fieldTextStyle,
      cursorColor: V3InputStyle.focused,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onFieldSubmitted: onSubmitted,
      onChanged: onChanged,
      validator: validator,
      decoration: decoration(
        label: label,
        hint: hint,
        icon: icon,
        suffixText: suffixText,
        isDense: isDense,
        suffixIcon: _buildSuffixActions(
          controller: controller,
          iconColor: V3InputStyle.icon,
          suffixIcon: suffixIcon,
          showPaste: showPaste,
          enabled: enabled,
        ),
      ),
    );
  }

  /// Search polje (hint + search ikona, clear, bez paste).
  static Widget searchField({
    required TextEditingController controller,
    required String hint,
    ValueChanged<String>? onChanged,
    VoidCallback? onClear,
    bool isDense = true,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool expands = false,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          style: fieldTextStyle,
          cursorColor: V3InputStyle.focused,
          textCapitalization: textCapitalization,
          expands: expands,
          maxLines: expands ? null : 1,
          onChanged: onChanged,
          decoration: decoration(
            hint: hint,
            icon: Icons.search,
            isDense: isDense,
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: V3InputStyle.icon),
                    onPressed: () {
                      controller.clear();
                      onClear?.call();
                      onChanged?.call('');
                    },
                  )
                : null,
          ),
        );
      },
    );
  }

  static Widget phoneField({
    required TextEditingController controller,
    String label = 'Broj telefona',
    String? hint,
    bool isRequired = true,
    bool enabled = true,
    ValueChanged<String>? onSubmitted,
  }) {
    return formField(
      controller: controller,
      label: label,
      icon: Icons.phone,
      hint: hint ?? '06x xxx xxxx',
      keyboardType: TextInputType.phone,
      enabled: enabled,
      onSubmitted: onSubmitted,
      validator: (v) => phoneValidator(v, isRequired: isRequired),
    );
  }

  static Widget numberField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? suffixText,
    String? Function(String?)? validator,
    bool isDense = false,
    bool enabled = true,
    bool showPaste = true,
    ValueChanged<String>? onChanged,
    TextInputType? keyboardType,
    IconData? icon,
  }) {
    return formField(
      controller: controller,
      label: label,
      icon: icon ?? Icons.numbers,
      hint: hint,
      keyboardType: keyboardType ?? const TextInputType.numberWithOptions(decimal: true),
      suffixText: suffixText,
      validator: validator,
      isDense: isDense,
      enabled: enabled,
      showPaste: showPaste,
      onChanged: onChanged,
    );
  }

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

  static String? requiredValidator(String? value, [String message = 'Ovo polje je obavezno']) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  static String? phoneValidator(String? value, {bool isRequired = true}) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return isRequired ? 'Broj telefona je obavezan' : null;
    }
    if ((normalized.startsWith('+') || normalized.startsWith('0') || normalized.startsWith('381')) &&
        !V3PhoneUtils.isValid(normalized)) {
      return 'Neispravan broj telefona';
    }
    return null;
  }
}