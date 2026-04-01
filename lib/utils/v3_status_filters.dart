class V3StatusFilters {
  V3StatusFilters._();

  static bool isActiveForDisplay({
    required bool aktivno,
    String? status,
    bool pokupljen = false,
  }) {
    if (!aktivno) return false;
    final normalized = (status ?? '').trim().toLowerCase();
    if (normalized == 'otkazano' || normalized == 'odbijeno') return false;
    return true;
  }
}
