class V3PutnikIdResolver {
  V3PutnikIdResolver._();

  /// Primarni izvor je `putnik_id`, a `created_by` služi kao kompatibilni fallback.
  static String fromRow(Map<String, dynamic> row) {
    return (row['putnik_id']?.toString() ?? row['created_by']?.toString() ?? '').trim();
  }

  /// Za lokalni putnik payload (profil/login): `id` > `v3_auth_id` > `putnik_id`.
  static String? fromPutnikData(Map<String, dynamic>? data) {
    if (data == null) return null;

    final direct = data['id']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final authId = data['v3_auth_id']?.toString().trim();
    if (authId != null && authId.isNotEmpty) return authId;

    final fallback = data['putnik_id']?.toString().trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;

    return null;
  }
}
