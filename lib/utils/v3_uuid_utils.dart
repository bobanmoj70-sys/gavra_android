class V3UuidUtils {
  V3UuidUtils._();

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static String? extractUuid(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final candidate = raw.contains(':') ? raw.split(':').last.trim() : raw.trim();
    if (_uuidRegex.hasMatch(candidate)) return candidate.toLowerCase();

    return null;
  }

  static String? normalizeUuid(
    String? raw, {
    String? fallback,
  }) {
    return extractUuid(raw) ?? extractUuid(fallback);
  }
}
