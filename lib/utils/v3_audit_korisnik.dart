class V3AuditKorisnik {
  V3AuditKorisnik._();

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static String? currentUserId() {
    return null;
  }

  static String? extractUuid(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final candidate = raw.contains(':') ? raw.split(':').last.trim() : raw.trim();
    if (_uuidRegex.hasMatch(candidate)) return candidate.toLowerCase();

    return null;
  }

  static String? normalize(
    String? raw, {
    String? fallback,
    bool useCurrentUser = true,
  }) {
    return extractUuid(raw) ?? extractUuid(fallback) ?? (useCurrentUser ? currentUserId() : null);
  }
}
