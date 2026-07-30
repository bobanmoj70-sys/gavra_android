import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/v3_belgrade_time.dart';

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
    final vreme = V3BelgradeTime.normalizeToHHmm(data['vreme'] ?? '');
    final datumIso = V3BelgradeTime.parseIsoDatePart(data['datum'] ?? '');
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

  Map<String, String> toMap() => {
        'vozac_id': vozacId,
        'datum': datumIso,
        'grad': grad,
        'vreme': vreme,
      };
}

// SharedPreferences keys for persisting the latest autostart payload.
// The payload is saved when a push arrives and consumed when the driver
// opens the app, so tracking can start without tapping the notification.
const String _kPendingVozacId = 'pending_auto_start_vozac_id';
const String _kPendingDatumIso = 'pending_auto_start_datum_iso';
const String _kPendingGrad = 'pending_auto_start_grad';
const String _kPendingVreme = 'pending_auto_start_vreme';

Future<void> v3SavePendingAutoStartPayload(V3AutoStartPayload payload) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPendingVozacId, payload.vozacId);
  await prefs.setString(_kPendingDatumIso, payload.datumIso);
  await prefs.setString(_kPendingGrad, payload.grad);
  await prefs.setString(_kPendingVreme, payload.vreme);
}

Future<V3AutoStartPayload?> v3LoadPendingAutoStartPayload() async {
  final prefs = await SharedPreferences.getInstance();
  final vozacId = (prefs.getString(_kPendingVozacId) ?? '').trim();
  final datumIso = (prefs.getString(_kPendingDatumIso) ?? '').trim();
  final grad = (prefs.getString(_kPendingGrad) ?? '').trim();
  final vreme = (prefs.getString(_kPendingVreme) ?? '').trim();
  final payload = V3AutoStartPayload(
    vozacId: vozacId,
    datumIso: datumIso,
    grad: grad,
    vreme: vreme,
  );
  return payload.isValid ? payload : null;
}

Future<void> v3ClearPendingAutoStartPayload() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kPendingVozacId);
  await prefs.remove(_kPendingDatumIso);
  await prefs.remove(_kPendingGrad);
  await prefs.remove(_kPendingVreme);
}
