class V3StatusFilters {
  V3StatusFilters._();

  static String normalizeStatus(String? status) {
    final normalized = (status ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'active':
        return 'aktivan';
      case 'inactive':
      case 'deleted':
        return 'neaktivan';
      case 'otkazan':
      case 'cancelled':
        return 'otkazano';
      case 'rejected':
        return 'odbijeno';
      case 'approved':
        return 'odobreno';
      case 'pending':
        return 'obrada';
      default:
        return normalized;
    }
  }

  static String deriveOperativnaStatus(Map<String, dynamic> row) {
    final otkazanoAt = (row['otkazano_at']?.toString() ?? '').trim();
    if (otkazanoAt.isNotEmpty) return 'otkazano';

    final altPre = (row['alternativa_pre_at']?.toString() ?? '').trim();
    final altPosle = (row['alternativa_posle_at']?.toString() ?? '').trim();
    if (altPre.isNotEmpty || altPosle.isNotEmpty) return 'alternativa';

    final polazakAt = (row['polazak_at']?.toString() ?? '').trim();
    if (polazakAt.isNotEmpty) return 'odobreno';

    return 'obrada';
  }

  static bool isCanceledOrRejected(String? status) {
    final normalized = normalizeStatus(status);
    return normalized == 'otkazano' || normalized == 'odbijeno';
  }

  static bool isCanceled(String? status) {
    return normalizeStatus(status) == 'otkazano';
  }

  static bool isPokupljenAt(Object? pokupljenAt) {
    if (pokupljenAt == null) return false;
    if (pokupljenAt is String) return pokupljenAt.trim().isNotEmpty;
    return true;
  }

  static bool isNaplacenAt(Object? naplacenAt) {
    if (naplacenAt == null) return false;
    if (naplacenAt is String) return naplacenAt.trim().isNotEmpty;
    return true;
  }

  static bool isRejected(String? status) {
    return normalizeStatus(status) == 'odbijeno';
  }

  static bool isApproved(String? status) {
    return normalizeStatus(status) == 'odobreno';
  }

  static bool isPending(String? status) {
    return normalizeStatus(status) == 'obrada';
  }

  static bool isOfferLike(String? status) {
    final normalized = normalizeStatus(status);
    return normalized == 'alternativa';
  }

  static bool isActionLocked({
    String? status,
    bool pokupljen = false,
  }) {
    return pokupljen || isPending(status);
  }

  static bool isExcludedFromOptimization({
    String? status,
    bool pokupljen = false,
  }) {
    return pokupljen || isCanceledOrRejected(status);
  }

  static bool isVisibleForDisplay({
    String? status,
    bool pokupljen = false,
  }) {
    if (isCanceledOrRejected(status)) return false;
    return true;
  }

  static bool isDodelaAktivna(String? status) {
    final normalized = normalizeStatus(status);
    return normalized == 'aktivan';
  }
}
