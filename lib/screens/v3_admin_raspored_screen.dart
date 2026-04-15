import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_status_filters.dart';
import '../utils/v3_time_utils.dart';
import '../utils/v3_uuid_utils.dart';
import '../widgets/v3_bottom_nav_bar_zimski.dart';
import '../widgets/v3_putnik_card.dart';

/// V3 ekran za upravljanje rasporedom vozača.
/// Admin dodeljuje vozača kroz `v3_trenutna_dodela` (operativna ostaje izvor stanja vožnje).
class V3AdminRasporedScreen extends StatefulWidget {
  const V3AdminRasporedScreen({super.key});

  @override
  State<V3AdminRasporedScreen> createState() => _V3AdminRasporedScreenState();
}

class _V3AdminRasporedScreenState extends State<V3AdminRasporedScreen> {
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  String _selectedDay = 'Ponedeljak';
  Map<String, String> _activeVozacByTerminId = const {};
  RealtimeChannel? _trenutnaDodelaChannel;

  /// ISO datum za izabrani dan u tekućoj nedelji.
  String get _selectedDatumIso =>
      V3DanHelper.datumIsoZaDanPuniUTekucojSedmici(_selectedDay, anchor: V3DanHelper.schedulingWeekAnchor());

  List<String> get _bcVremena => getRasporedVremena('bc', navBarTypeNotifier.value, day: _selectedDay);
  List<String> get _vsVremena => getRasporedVremena('vs', navBarTypeNotifier.value, day: _selectedDay);
  List<String> get _sviPolasci => [
        ..._bcVremena.map((v) => '$v BC'),
        ..._vsVremena.map((v) => '$v VS'),
      ];

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
    return hour * 60 + minute;
  }

  String _normVreme(String? v) {
    if (v == null || v.isEmpty) return '';
    final p = v.split(':');
    if (p.length >= 2) {
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      return V3DanHelper.formatVreme(h, m);
    }
    return v;
  }

  Future<void> _reloadTrenutnaDodelaMap() async {
    try {
      final rows = await supabase
          .from('v3_trenutna_dodela')
          .select('termin_id, vozac_v3_auth_id, status')
          .eq('status', 'aktivan');
      final next = <String, String>{};
      for (final row in (rows as List<dynamic>)) {
        final mapped = row as Map<String, dynamic>;
        final status = mapped['status']?.toString() ?? '';
        if (!V3StatusFilters.isDodelaAktivna(status)) continue;
        final terminId = mapped['termin_id']?.toString().trim() ?? '';
        final vozacId = mapped['vozac_v3_auth_id']?.toString().trim() ?? '';
        if (terminId.isEmpty || vozacId.isEmpty) continue;
        next[terminId] = vozacId;
      }
      _activeVozacByTerminId = next;
    } catch (e) {
      debugPrint('[V3AdminRasporedScreen] _reloadTrenutnaDodelaMap error: $e');
      _activeVozacByTerminId = const {};
    }
  }

  String _vozacIdForOperativnaRow(Map<String, dynamic> row) {
    final terminId = row['id']?.toString().trim() ?? '';
    if (terminId.isEmpty) return '';
    return _activeVozacByTerminId[terminId] ?? '';
  }

  void _startTrenutnaDodelaRealtime() {
    final existing = _trenutnaDodelaChannel;
    if (existing != null) {
      supabase.removeChannel(existing);
      _trenutnaDodelaChannel = null;
    }

    final channel = supabase.channel('v3_trenutna_dodela_admin_raspored');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'v3_trenutna_dodela',
      callback: (_) {
        _refreshDodelaFromRealtime();
      },
    );
    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.channelError && error != null) {
        debugPrint('[V3AdminRasporedScreen] dodela realtime channelError: $error');
      }
      if (status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[V3AdminRasporedScreen] dodela realtime timedOut');
      }
    });

    _trenutnaDodelaChannel = channel;
  }

  Future<void> _refreshDodelaFromRealtime() async {
    if (!mounted) return;
    await _reloadTrenutnaDodelaMap();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = V3DanHelper.defaultWorkdayFullName();
    _startTrenutnaDodelaRealtime();
    _initData();
  }

  Future<void> _initData() async {
    await _reloadTrenutnaDodelaMap();
    if (!mounted) return;
    setState(() {
      _syncSelectedSlotForDay();
    });
  }

  @override
  void dispose() {
    final channel = _trenutnaDodelaChannel;
    _trenutnaDodelaChannel = null;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    super.dispose();
  }

  void _autoSelectNajblizeVreme() {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final svi = _sviPolasci;
    if (svi.isEmpty) {
      _selectedVreme = '';
      return;
    }

    String? bestGrad;
    String? bestVreme;
    int minDiff = 99999;
    for (final polazak in svi) {
      final parts = polazak.split(' ');
      if (parts.length < 2) continue;
      final vreme = _normVreme(parts[0]);
      final grad = parts.sublist(1).join(' ').toUpperCase();
      final mins = _timeToMinutes(vreme);
      if (mins < 0) continue;
      final diff = (mins - nowMin).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestGrad = grad;
        bestVreme = vreme;
      }
    }

    if (bestGrad != null && bestVreme != null) {
      _selectedGrad = bestGrad;
      _selectedVreme = bestVreme;
    }
  }

  void _syncSelectedSlotForDay() {
    final rm = V3MasterRealtimeManager.instance;
    final datum = _selectedDatumIso;
    final currentNorm = V3TimeUtils.normalizeToHHmm(_selectedVreme);

    final uniqueSlots = <String, Map<String, String>>{};
    for (final row in rm.operativnaNedeljaCache.values) {
      final putnikId = row['created_by']?.toString() ?? '';
      if (!_putnikPostoji(putnikId)) continue;
      if (V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '') != datum) continue;
      final statusFinal = V3StatusFilters.deriveOperativnaStatus(row);
      if (V3StatusFilters.isCanceledOrRejected(statusFinal) ||
          V3StatusFilters.normalizeStatus(statusFinal) == 'obrada') {
        continue;
      }

      final grad = (row['grad']?.toString() ?? '').toUpperCase();
      final vreme = V3TimeUtils.normalizeToHHmm(_effectiveTime(row));
      if (grad.isEmpty || vreme.isEmpty) continue;

      final key = '$grad|$vreme';
      uniqueSlots.putIfAbsent(key, () => {'grad': grad, 'vreme': vreme});
    }

    if (uniqueSlots.isEmpty) {
      _autoSelectNajblizeVreme();
      return;
    }

    final currentExists =
        uniqueSlots.values.any((slot) => slot['grad'] == _selectedGrad && slot['vreme'] == currentNorm);
    if (currentExists) return;

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final slots = uniqueSlots.values.toList();
    slots.sort((a, b) {
      final aVreme = _normVreme(a['vreme']);
      final bVreme = _normVreme(b['vreme']);
      final aDiff = _timeToMinutes(aVreme) < 0 ? 99999 : (_timeToMinutes(aVreme) - nowMin).abs();
      final bDiff = _timeToMinutes(bVreme) < 0 ? 99999 : (_timeToMinutes(bVreme) - nowMin).abs();
      if (aDiff != bDiff) return aDiff.compareTo(bDiff);
      final byGrad = (a['grad'] ?? '').compareTo(b['grad'] ?? '');
      if (byGrad != 0) return byGrad;
      return aVreme.compareTo(bVreme);
    });

    final selected = slots.first;
    _selectedGrad = selected['grad'] ?? _selectedGrad;
    _selectedVreme = _normVreme(selected['vreme']);
  }

  // ─── Cache helpers ────────────────────────────────────────────────────────

  String _effectiveTime(Map<String, dynamic> row) {
    return ((row['polazak_at'] as String?) ?? '').trim();
  }

  bool _putnikPostoji(String putnikId) {
    final putnik = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    return putnik != null;
  }

  /// Vozač za termin iz trenutne dodele (bez fallback-a).
  V3Vozac? _getVozacZaTermin(String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final normV = V3TimeUtils.normalizeToHHmm(vreme);
    final datum = _selectedDatumIso;

    final terminRows = rm.operativnaNedeljaCache.values.where((row) {
      final rowVreme = _effectiveTime(row);
      final statusFinal = V3StatusFilters.deriveOperativnaStatus(row);
      final putnikId = row['created_by']?.toString() ?? '';
      return V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '') == datum &&
          row['grad'] == grad &&
          _putnikPostoji(putnikId) &&
          !V3StatusFilters.isCanceledOrRejected(statusFinal) &&
          V3TimeUtils.normalizeToHHmm(rowVreme) == normV;
    }).toList();

    if (terminRows.isEmpty) return null;

    String? zajednickiVozacId;
    for (final row in terminRows) {
      final vozacId = _vozacIdForOperativnaRow(row).trim();
      if (vozacId.isEmpty) {
        return null;
      }
      if (zajednickiVozacId == null) {
        zajednickiVozacId = vozacId;
      } else if (zajednickiVozacId != vozacId) {
        return null;
      }
    }

    if (zajednickiVozacId == null) return null;
    return V3VozacService.getVozacById(zajednickiVozacId);
  }

  /// Vozač za putnika iz trenutne dodele (bez fallback-a).
  V3Vozac? _getVozacZaPutnika(String putnikId, String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final normV = V3TimeUtils.normalizeToHHmm(vreme);
    final datum = _selectedDatumIso;

    for (final row in rm.operativnaNedeljaCache.values) {
      final rowVreme = _effectiveTime(row);
      final statusFinal = V3StatusFilters.deriveOperativnaStatus(row);
      if (row['created_by'] == putnikId &&
          row['grad'] == grad &&
          !V3StatusFilters.isCanceledOrRejected(statusFinal) &&
          V3TimeUtils.normalizeToHHmm(rowVreme) == normV &&
          V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '') == datum) {
        final vozacId = _vozacIdForOperativnaRow(row);
        if (vozacId.isNotEmpty) {
          final vozac = V3VozacService.getVozacById(vozacId);
          if (vozac != null) return vozac;
        }
      }
    }
    return null;
  }

  int _getPutnikCount(String grad, String vreme) {
    final normV = V3TimeUtils.normalizeToHHmm(vreme);
    final targetDatum = _selectedDatumIso;

    // Ispravka: koristi v3_operativna_nedelja cache i broji broj_mesta
    return V3MasterRealtimeManager.instance.operativnaNedeljaCache.values.where((r) {
      final datumStr = r['datum'] as String?;
      if (datumStr == null) return false;
      final d = V3DanHelper.parseIsoDatePart(datumStr);
      final statusFinal = V3StatusFilters.deriveOperativnaStatus(r);
      final putnikId = r['created_by']?.toString() ?? '';
      return d == targetDatum &&
          r['grad'] == grad &&
          V3TimeUtils.normalizeToHHmm((r['polazak_at']) as String? ?? '') == normV &&
          _putnikPostoji(putnikId) &&
          !V3StatusFilters.isCanceledOrRejected(statusFinal) &&
          V3StatusFilters.normalizeStatus(statusFinal) != 'obrada';
    }).fold(0, (sum, r) => sum + ((r['broj_mesta'] as int?) ?? 1));
  }

  Color? _getVozacBoja(String grad, String vreme) {
    final v = _getVozacZaTermin(grad, vreme);
    return v != null ? _parseColor(v.boja) : null;
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blueAccent;
    final h = hex.replaceAll('#', '');
    try {
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  // ─── DB operacije ─────────────────────────────────────────────────────────

  Future<void> _dodelijTermin(String grad, String vreme, V3Vozac vozac) async {
    try {
      final datum = _selectedDatumIso;
      final actorUuid = V3UuidUtils.normalizeUuid(
        V3VozacService.currentVozac?.id,
      );

      // Pronađi sve putnike iz operativne nedelje za ovaj termin
      final rm = V3MasterRealtimeManager.instance;
      final putnici = rm.operativnaNedeljaCache.values.where((r) {
        final datumStr = r['datum'] as String?;
        if (datumStr == null) return false;
        final d = V3DanHelper.parseIsoDatePart(datumStr);
        final rowVreme = _effectiveTime(r);
        final putnikId = r['created_by']?.toString() ?? '';
        return d == datum &&
            r['grad'] == grad &&
            V3TimeUtils.normalizeToHHmm(rowVreme) == V3TimeUtils.normalizeToHHmm(vreme) &&
            _putnikPostoji(putnikId) &&
            !V3StatusFilters.isCanceledOrRejected(V3StatusFilters.deriveOperativnaStatus(r));
      }).toList();

      final operativnaIds = putnici
          .map((entry) => entry['id']?.toString())
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList();

      for (final row in putnici) {
        final operativnaId = row['id']?.toString() ?? '';
        final putnikId = row['created_by']?.toString() ?? '';
        if (operativnaId.isEmpty || putnikId.isEmpty) continue;

        await supabase.from('v3_trenutna_dodela').upsert({
          'termin_id': operativnaId,
          'putnik_v3_auth_id': putnikId,
          'vozac_v3_auth_id': vozac.id,
          'status': 'aktivan',
          if (actorUuid != null) 'updated_by': actorUuid,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'termin_id');
      }

      await _reloadTrenutnaDodelaMap();
      if (mounted) setState(() {});

      if (mounted) {
        V3AppSnackBar.success(
            context,
            '✅ ${vozac.imePrezime} → $grad $vreme ($datum)\n'
            '📋 ${operativnaIds.length} putnika raspoređeno');
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _ukloniTermin(String grad, String vreme) async {
    try {
      final normVreme = V3TimeUtils.normalizeToHHmm(vreme);
      final operativnaIds = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values
          .where((r) {
            final datumStr = r['datum'] as String?;
            if (datumStr == null) return false;
            final d = V3DanHelper.parseIsoDatePart(datumStr);
            final rowVreme = _effectiveTime(r);
            final putnikId = r['created_by']?.toString() ?? '';
            return d == _selectedDatumIso &&
                r['grad'] == grad &&
                V3TimeUtils.normalizeToHHmm(rowVreme) == normVreme &&
                _putnikPostoji(putnikId) &&
                !V3StatusFilters.isCanceledOrRejected(V3StatusFilters.deriveOperativnaStatus(r));
          })
          .map((r) => r['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      for (final operativnaId in operativnaIds) {
        await supabase.from('v3_trenutna_dodela').delete().eq('termin_id', operativnaId);
      }

      await _reloadTrenutnaDodelaMap();
      if (mounted) setState(() {});

      if (mounted) V3AppSnackBar.success(context, '🗑️ Dodjela uklonjena: $grad $vreme ($_selectedDatumIso)');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _dodelijPutniku(String putnikId, V3Vozac vozac, String grad, String vreme) async {
    try {
      final datum = _selectedDatumIso;
      final actorUuid = V3UuidUtils.normalizeUuid(
        V3VozacService.currentVozac?.id,
      );
      final normVreme = V3TimeUtils.normalizeToHHmm(vreme);
      final operativna = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values.firstWhere(
        (r) =>
            r['created_by'] == putnikId &&
            V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '') == datum &&
            r['grad'] == grad &&
            V3TimeUtils.normalizeToHHmm(_effectiveTime(r)) == normVreme &&
            !V3StatusFilters.isCanceledOrRejected(V3StatusFilters.deriveOperativnaStatus(r)),
        orElse: () => <String, dynamic>{},
      );

      if (operativna.isEmpty) {
        if (mounted) V3AppSnackBar.warning(context, '⚠️ Nema operativnog reda za izabranog putnika/termin');
        return;
      }

      final operativnaId = operativna['id'] as String;
      await supabase.from('v3_trenutna_dodela').upsert({
        'termin_id': operativnaId,
        'putnik_v3_auth_id': putnikId,
        'vozac_v3_auth_id': vozac.id,
        'status': 'aktivan',
        if (actorUuid != null) 'updated_by': actorUuid,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'termin_id');

      await _reloadTrenutnaDodelaMap();
      if (mounted) setState(() {});

      if (mounted) V3AppSnackBar.success(context, '✅ ${vozac.imePrezime} → putnik ($datum)');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _ukloniPutnikDodjelu(String putnikId, String grad, String vreme) async {
    try {
      final normVreme = V3TimeUtils.normalizeToHHmm(vreme);
      final operativna = V3MasterRealtimeManager.instance.operativnaNedeljaCache.values.firstWhere(
        (r) =>
            r['created_by'] == putnikId &&
            V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '') == _selectedDatumIso &&
            r['grad'] == grad &&
            V3TimeUtils.normalizeToHHmm(_effectiveTime(r)) == normVreme &&
            !V3StatusFilters.isCanceledOrRejected(V3StatusFilters.deriveOperativnaStatus(r)),
        orElse: () => <String, dynamic>{},
      );

      if (operativna.isNotEmpty) {
        final operativnaId = operativna['id']?.toString() ?? '';
        if (operativnaId.isNotEmpty) {
          await supabase.from('v3_trenutna_dodela').delete().eq('termin_id', operativnaId);
        }
      }

      await _reloadTrenutnaDodelaMap();
      if (mounted) setState(() {});

      if (mounted) V3AppSnackBar.success(context, '🗑️ Individualna dodjela uklonjena');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  // ─── Dialozi ──────────────────────────────────────────────────────────────

  Future<void> _showTerminAssignDialog(String grad, String vreme) async {
    final trenutni = _getVozacZaTermin(grad, vreme);
    V3Vozac? odabran = trenutni;
    final vozaci = V3VozacService.getAllVozaci();
    if (vozaci.isEmpty) {
      if (mounted) V3AppSnackBar.warning(context, 'Nema registrovanih vozača');
      return;
    }

    await V3DialogHelper.showBottomSheetBuilder<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                width: 40,
                height: V3ContainerUtils.responsiveHeight(context, 4, intensity: 0.2),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              Text('🗓️ TERMIN: $grad $vreme — $_selectedDatumIso',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
              const SizedBox(height: 6),
              const Text('Dodeli vozača terminu',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              ...vozaci.map((v) => _vozacTile(
                    ime: v.imePrezime,
                    isSelected: odabran?.id == v.id,
                    color: _parseColor(v.boja),
                    onTap: () => setS(() => odabran = odabran?.id == v.id ? null : v),
                  )),
              const SizedBox(height: 8),
              if (trenutni != null)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _ukloniTermin(grad, vreme);
                  },
                  icon: const Icon(Icons.clear, color: Colors.redAccent, size: 18),
                  label: const Text('Ukloni dodjelu termina', style: TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: V3ButtonUtils.elevatedButton(
                  onPressed: odabran == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _dodelijTermin(grad, vreme, odabran!);
                        },
                  text: 'Potvrdi',
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPutnikAssignDialog(V3OperativnaNedeljaEntry termin) async {
    final trenutni = _getVozacZaPutnika(termin.putnikId, _selectedGrad, _selectedVreme);
    V3Vozac? odabran = trenutni;
    final vozaci = V3VozacService.getAllVozaci();
    if (vozaci.isEmpty) {
      if (mounted) V3AppSnackBar.warning(context, 'Nema registrovanih vozača');
      return;
    }

    await V3DialogHelper.showBottomSheetBuilder<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                width: 40,
                height: V3ContainerUtils.responsiveHeight(context, 4, intensity: 0.2),
                decoration:
                    BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              Text('👤 ${(V3PutnikService.getPutnikById(termin.putnikId)?.imePrezime ?? 'Putnik').toUpperCase()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
              Text('$_selectedGrad $_selectedVreme — $_selectedDatumIso',
                  style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 8),
              const Text('Dodeli vozača putniku',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              ...vozaci.map((v) => _vozacTile(
                    ime: v.imePrezime,
                    isSelected: odabran?.id == v.id,
                    color: _parseColor(v.boja),
                    onTap: () => setS(() => odabran = odabran?.id == v.id ? null : v),
                  )),
              const SizedBox(height: 8),
              if (trenutni != null)
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _ukloniPutnikDodjelu(termin.putnikId, _selectedGrad, _selectedVreme);
                  },
                  icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent, size: 18),
                  label: const Text('Ukloni individualnu dodjelu', style: TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: V3ButtonUtils.elevatedButton(
                  onPressed: odabran == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _dodelijPutniku(termin.putnikId, odabran!, _selectedGrad, _selectedVreme);
                        },
                  text: 'Potvrdi',
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<V3OperativnaNedeljaEntry>>(
      stream: V3MasterRealtimeManager.instance.v3StreamFromCache<List<V3OperativnaNedeljaEntry>>(
        tables: const [
          'v3_operativna_nedelja',
          'v3_auth',
          'v3_adrese',
          'v3_kapacitet_slots',
        ],
        build: () => V3OperativnaNedeljaService.getOperativnaNedeljaByDatum(_selectedDatumIso),
      ),
      builder: (context, snapshot) {
        final sviZapisi = snapshot.data ?? [];
        final vozacTermin = _getVozacZaTermin(_selectedGrad, _selectedVreme);
        String slotVreme(V3OperativnaNedeljaEntry z) => z.polazakAt ?? '';

        // Zapisi iz operativna_nedelja za selektovani grad+vreme (datum već filtriran streamom)
        final zapisi = _selectedVreme.isNotEmpty
            ? (sviZapisi
                .where((z) =>
                    z.grad == _selectedGrad &&
                    !V3StatusFilters.isCanceledOrRejected(z.statusFinal) &&
                    _putnikPostoji(z.putnikId) &&
                    V3TimeUtils.normalizeToHHmm(slotVreme(z)) == V3TimeUtils.normalizeToHHmm(_selectedVreme) &&
                    !V3StatusFilters.isRejected(z.statusFinal))
                .toList()
              ..sort((a, b) {
                // Zatim po statusu (otkazano na kraj)
                final aOtk = V3StatusFilters.isCanceled(a.statusFinal) ? 1 : 0;
                final bOtk = V3StatusFilters.isCanceled(b.statusFinal) ? 1 : 0;
                return aOtk.compareTo(bOtk);
              }))
            : <V3OperativnaNedeljaEntry>[];

        return Scaffold(
          extendBodyBehindAppBar: true,
          extendBody: true,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              '🚗 Raspored vozača',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: Container(
            decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
            child: SafeArea(
              child: Column(
                children: [
                  // ── Dan chips ──────────────────────────────────────────
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: V3DanHelper.workdayNames.map((day) {
                        final isSelected = _selectedDay == day;
                        final abbr = V3DanHelper.workdayAbbrFromFullName(day);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() {
                              _selectedDay = V3DanHelper.normalizeToWorkdayFull(day);
                              _syncSelectedSlotForDay();
                            }),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : Theme.of(context).glassContainer.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      isSelected ? Colors.white.withValues(alpha: 0.7) : Theme.of(context).glassBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                abbr.toUpperCase(),
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white60,
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                  fontSize: 13,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // ── Termin info traka ──────────────────────────────────
                  if (_selectedVreme.isNotEmpty)
                    _terminInfoTraka(
                      grad: _selectedGrad,
                      vreme: _selectedVreme,
                      vozac: vozacTermin,
                      onTap: () => _showTerminAssignDialog(_selectedGrad, _selectedVreme),
                    ),

                  // ── Lista termina ──────────────────────────────────────
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.zero,
                            child: _selectedVreme.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.inbox, size: 48, color: Colors.white.withValues(alpha: 0.3)),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Odaberi polazak u donjem meniju',
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  )
                                : zapisi.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.people_outline,
                                                size: 48, color: Colors.white.withValues(alpha: 0.3)),
                                            const SizedBox(height: 12),
                                            Text(
                                              'Nema putnika za ovaj polazak',
                                              style:
                                                  TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: zapisi.length,
                                        itemBuilder: (_, i) {
                                          final z = zapisi[i];
                                          final redniBroj = zapisi.sublist(0, i).fold(1, (sum, e) => sum + e.brojMesta);
                                          final terminDodeljen = vozacTermin != null;
                                          final indivVozac =
                                              _getVozacZaPutnika(z.putnikId, _selectedGrad, slotVreme(z));
                                          final vozacBoja = indivVozac != null
                                              ? _parseColor(indivVozac.boja)
                                              : (terminDodeljen ? _parseColor(vozacTermin.boja) : null);

                                          final putnik = V3PutnikService.getPutnikById(z.putnikId);
                                          if (putnik == null) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: V3PutnikCard(
                                              putnik: putnik,
                                              entry: z,
                                              redniBroj: redniBroj,
                                              vozacBoja: vozacBoja,
                                              onDodeliVozaca: V3StatusFilters.isCanceled(z.statusFinal)
                                                  ? null
                                                  : () => _showPutnikAssignDialog(z),
                                              onChanged: () => setState(() {}),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: ValueListenableBuilder<String>(
            valueListenable: navBarTypeNotifier,
            builder: (context, navType, _) {
              final commonProps = _buildNavBarProps();
              // Zimski raspored widget generički hendluje i zimsku i custom varijantu
              return V3BottomNavBarZimski(
                sviPolasci: commonProps.sviPolasci,
                selectedGrad: commonProps.selectedGrad,
                selectedVreme: commonProps.selectedVreme,
                onPolazakChanged: commonProps.onChanged,
                getPutnikCount: commonProps.getCount,
                getKapacitet: commonProps.getKapacitet,
                showVozacBoja: true,
                getVozacColor: _getVozacBoja,
                bcVremena: _bcVremena,
                vsVremena: _vsVremena,
              );
            },
          ),
        );
      },
    );
  }

  _NavBarProps _buildNavBarProps() => _NavBarProps(
        sviPolasci: _sviPolasci,
        selectedGrad: _selectedGrad,
        selectedVreme: _selectedVreme,
        onChanged: (grad, vreme) => setState(() {
          _selectedGrad = grad;
          _selectedVreme = vreme;
        }),
        getCount: _getPutnikCount,
        getKapacitet: (grad, vreme) {
          final datum = DateTime.tryParse(_selectedDatumIso) ?? DateTime.now();
          return V3OperativnaNedeljaService.getKapacitetVozila(grad, vreme, datum);
        },
      );

  // ─── Termin info traka ────────────────────────────────────────────────────
  Widget _terminInfoTraka({
    required String grad,
    required String vreme,
    required V3Vozac? vozac,
    required VoidCallback onTap,
  }) {
    final color = vozac != null ? _parseColor(vozac.boja) : Colors.white24;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.directions_car, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                vozac != null ? 'Vozač: ${vozac.imePrezime}' : 'Nema dodjele — tap za dodjelu vozača',
                style: TextStyle(
                  color: vozac != null ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Text('$grad $vreme', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, color: color.withValues(alpha: 0.7), size: 16),
          ],
        ),
      ),
    );
  }

  // ─── Vozač tile za bottom sheet ───────────────────────────────────────────
  Widget _vozacTile({
    required String ime,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.15),
              width: isSelected ? 1 : 0.6,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withValues(alpha: 0.3),
                child: Text(
                  ime.isNotEmpty ? ime[0].toUpperCase() : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ime,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── NavBar props helper ──────────────────────────────────────────────────────
class _NavBarProps {
  final List<String> sviPolasci;
  final String selectedGrad;
  final String selectedVreme;
  final void Function(String, String) onChanged;
  final int Function(String, String) getCount;
  final int? Function(String, String) getKapacitet;

  const _NavBarProps({
    required this.sviPolasci,
    required this.selectedGrad,
    required this.selectedVreme,
    required this.onChanged,
    required this.getCount,
    required this.getKapacitet,
  });
}

// ─── Termin tile ──────────────────────────────────────────────────────────────
