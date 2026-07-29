import '../../utils/v3_date_utils.dart';
import '../../utils/v3_time_utils.dart';

/// Immutable, normalized payload for `vozac_auto_start_tracking` push.
///
/// This is the single source of truth for parsing and normalizing the FCM
/// data fields that trigger automatic driver tracking. All call sites
/// (foreground handler, background handler, launch handler and the driver
/// screen) should use this class instead of duplicating the parsing logic.
class V3AutoStartPayload {
  const V3AutoStartPayload({
    required this.vozacId,
    required this.datumIso,
    required this.grad,
    required this.vreme,
  });

  /// Parses a string-keyed FCM data map into a normalized payload.
  ///
  /// Recognizes `v3_auth_id` and falls back to `vozac_id` for the driver id.
  /// Normalizes `grad` to uppercase, `vreme` to HH:mm and `datum` to the
  /// ISO date part (yyyy-MM-dd).
  factory V3AutoStartPayload.fromMap(Map<String, String> data) {
    final vozacId = (data['v3_auth_id'] ?? data['vozac_id'] ?? '').trim();
    final grad = (data['grad'] ?? '').trim().toUpperCase();
    final vreme = V3TimeUtils.normalizeToHHmm(data['vreme'] ?? '');
    final datumIso = V3DateUtils.parseIsoDatePart(data['datum'] ?? '');
    return V3AutoStartPayload(
      vozacId: vozacId,
      datumIso: datumIso,
      grad: grad,
      vreme: vreme,
    );
  }

  final String vozacId;
  final String datumIso;
  final String grad;
  final String vreme;

  bool get isValid => vozacId.isNotEmpty && datumIso.isNotEmpty && grad.isNotEmpty && vreme.isNotEmpty;

  /// Returns true when this payload describes the same driver/session that is
  /// currently being tracked by [V3VozacLocationTrackingService].
  bool matchesCurrentSession({
    required String? activeVozacId,
    required String activeDatumIso,
    required String activeGrad,
    required String activeVreme,
  }) {
    return vozacId == (activeVozacId ?? '') && datumIso == activeDatumIso && grad == activeGrad && vreme == activeVreme;
  }
}
