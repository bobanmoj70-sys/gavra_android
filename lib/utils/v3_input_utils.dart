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

  /// Labela iznad polja (čitljiva na tamnoj dijalog pozadini).
  static const Color externalLabel = Color(0xFFCBD5E1);
  static const double externalLabelGap = 6;
}

/// V3InputUtils — jedan izvor istine za TextField / TextFormField / dropdown / search.
///
/// **Pravilo:** labele su UVEK iznad polja (nikad floating na ivici outline-a).
/// Floating label na tamnoj pozadini se „prelama“ — zato je zabranjen u [decoration].
class V3InputUtils {
  V3InputUtils._();

  // ─── Jedna istina: eksterna labela ───────────────────────────────────────

  static TextStyle get externalLabelStyle => const TextStyle(
        color: V3InputStyle.externalLabel,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.2,
      );

  /// Omota [child] labelom iznad. Koristi za dropdown / InputDecorator / custom polja.
  static Widget labeled({
    String? label,
    required Widget child,
    Color? labelColor,
    double gap = V3InputStyle.externalLabelGap,
  }) {
    final text = label?.trim();
    if (text == null || text.isEmpty) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: labelColor != null ? externalLabelStyle.copyWith(color: labelColor) : externalLabelStyle,
        ),
        SizedBox(height: gap),
        child,
      ],
    );
  }

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

  /// Samo chrome polja — **bez** floating/labelText (label ide preko [labeled]).
  ///
  /// Parametar [label] se ignoriše u decoration-u (zadržan radi kompatibilnosti poziva);
  /// koristi [labeled] ili field buildere koji sami omotaju labelu.
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
    // [label] namerno nije u InputDecoration — vidi [labeled] / field buildere.
    final fill = fillColor ?? V3InputStyle.fill;
    final borderCol = borderColor ?? V3InputStyle.border;
    final focused = focusedBorderColor ?? V3InputStyle.focused;
    final labelCol = textColor != null ? textColor.withValues(alpha: 0.72) : V3InputStyle.label;
    final hintCol = textColor != null ? textColor.withValues(alpha: 0.45) : V3InputStyle.hint;
    final iconCol = iconColor ?? V3InputStyle.icon;
    final r = BorderRadius.circular(V3InputStyle.radius);

    return InputDecoration(
      // Nikad floating label — jedna istina za celu app.
      labelText: null,
      floatingLabelBehavior: FloatingLabelBehavior.never,
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

  /// Decoration za dropdown/InputDecorator. [label] se ne crta ovde — koristi [labeled].
  static InputDecoration dropdownDecoration({
    String? label,
    IconData? icon,
    Widget? suffixIcon,
    Color? prefixIconColor,
    bool isDense = true,
    String? hint,
  }) {
    return decoration(
      hint: hint,
      icon: icon,
      suffixIcon: suffixIcon,
      isDense: isDense,
      iconColor: prefixIconColor ?? V3InputStyle.icon,
    );
  }

  static TextStyle get fieldTextStyle => const TextStyle(color: V3InputStyle.text, fontWeight: FontWeight.w500);

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

    return labeled(
      label: label,
      child: TextField(
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
    return labeled(
      label: label,
      child: TextFormField(
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
      ),
    );
  }

  /// Search polje (hint + search ikona, clear, bez paste) — bez eksterne labele.
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
    String? label,
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
