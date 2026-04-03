class V3TimeUtils {
  V3TimeUtils._();

  static final RegExp _timeRegex = RegExp(
    r'((?:[01]?\d|2[0-3]):[0-5]\d(?:\:[0-5]\d)?)',
  );

  static String normalizeToHHmm(String? value) {
    if (value == null || value.trim().isEmpty) return '';

    final match = _timeRegex.firstMatch(value);
    if (match == null) return value.trim();

    final raw = match.group(1)!;
    final parts = raw.split(':');
    if (parts.length < 2) return raw;

    final hour = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final minute = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String? extractHHmmToken(String? value) {
    if (value == null || value.trim().isEmpty) return null;

    final match = _timeRegex.firstMatch(value);
    if (match == null) return null;

    final raw = match.group(1)!;
    final parts = raw.split(':');
    if (parts.length < 2) return null;

    final hour = (int.tryParse(parts[0]) ?? 0).toString().padLeft(2, '0');
    final minute = (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
