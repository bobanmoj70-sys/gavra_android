import '../globals.dart';

class V3AuditActor {
  V3AuditActor._();

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static String? _extractUuid(String? raw) {
    final input = (raw ?? '').trim();
    if (input.isEmpty) return null;

    final candidate = input.contains(':') ? input.split(':').last.trim() : input;
    if (_uuidRegex.hasMatch(candidate)) return candidate.toLowerCase();
    return null;
  }

  static String? currentUserId() {
    return _extractUuid(supabase.auth.currentUser?.id);
  }

  static String? normalize(
    String? raw, {
    String? fallback,
    bool useCurrentUser = true,
  }) {
    return _extractUuid(raw) ?? _extractUuid(fallback) ?? (useCurrentUser ? currentUserId() : null);
  }

  static String? cron([String? source]) {
    return normalize(source);
  }

  static String? admin([String? source]) {
    return normalize(source);
  }

  static String? vozac([String? vozacId]) {
    return normalize(vozacId);
  }

  static String? putnik([String? putnikId]) {
    return normalize(putnikId);
  }
}
