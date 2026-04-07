class V3StatusFilters {
  V3StatusFilters._();

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
