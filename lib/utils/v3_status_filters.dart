class V3StatusFilters {
  V3StatusFilters._();

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

  static String normalizeStatus(String? status) {
    return (status ?? '').trim().toLowerCase();
  }

  static bool isCanceledOrRejected(String? status) {
    final normalized = normalizeStatus(status);
    return normalized == 'otkazano' || normalized == 'odbijeno';
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
}
