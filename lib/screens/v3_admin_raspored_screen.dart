import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v3_putnik.dart';
import '../models/v3_vozac.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_dodela_orchestrator_service.dart';
import '../services/v3/v3_dodela_resolver_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_trenutna_dodela_service.dart';
import '../services/v3/v3_trenutna_dodela_slot_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_date_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_time_utils.dart';
import '../utils/v3_uuid_utils.dart';
import '../widgets/v3_bottom_nav_bar_slotovi.dart';
import '../widgets/v3_putnik_card.dart';

/// V3 ekran za upravljanje rasporedom vozača.
/// Admin dodeljuje vozača kroz `v3_trenutna_dodela`
/// (operativna ostaje izvor stanja vožnje i putnika).
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
  Map<String, String> _activeVozacBySlotKey = const {};
  RealtimeChannel? _trenutnaDodelaChannel;
  int _dodelaReconnectAttempts = 0;

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

  Future<void> _reloadTrenutnaDodelaMap() async {
    try {
      final maps = await V3DodelaResolverService.loadActiveAssignments();
      _activeVozacByTerminId = maps.byTerminId;
      _activeVozacBySlotKey = maps.bySlotKey;
    } catch (e) {
      debugPrint('[V3AdminRasporedScreen] _reloadTrenutnaDodelaMap error: $e');
      _activeVozacByTerminId = const {};
      _activeVozacBySlotKey = const {};
    }
  }

  String _vozacIdForOperativnaRow(Map<String, dynamic> row) {
    return V3DodelaResolverService.resolveVozacIdForOperativnaRow(
      row: row,
      activeVozacByTerminId: _activeVozacByTerminId,
      activeVozacBySlotKey: _activeVozacBySlotKey,
      vremeKolona: 'polazak_at',
    );
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
      table: V3TrenutnaDodelaService.tableName,
      callback: (_) {
        _refreshDodelaFromRealtime();
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: V3TrenutnaDodelaSlotService.tableName,
      callback: (_) {
        _refreshDodelaFromRealtime();
      },
    );
    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _dodelaReconnectAttempts = 0;
      }
      if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[V3AdminRasporedScreen] dodela realtime $status: $error');
        if (mounted) {
          _dodelaReconnectAttempts += 1;
          final capped = _dodelaReconnectAttempts.clamp(1, 5);
          final delayMs = 500 * (1 << capped);
          Future<void>.delayed(Duration(milliseconds: delayMs), () {
            if (mounted) _startTrenutnaDodelaRealtime();
          });
        }
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
      final vreme = V3TimeUtils.normalizeToHHmm(parts[0]);
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
      if (!_putnikPostoji(putnikId) || V3DateUtils.parseIsoDatePart(row['datum'] as String? ?? '') != datum) continue;

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
      final aVreme = V3TimeUtils.normalizeToHHmm(a['vreme']);
      final bVreme = V3TimeUtils.normalizeToHHmm(b['vreme']);
      final aDiff = _timeToMinutes(aVreme) < 0 ? 99999 : (_timeToMinutes(aVreme) - nowMin).abs();
      final bDiff = _timeToMinutes(bVreme) < 0 ? 99999 : (_timeToMinutes(bVreme) - nowMin).abs();
      if (aDiff != bDiff) return aDiff.compareTo(bDiff);
      final byGrad = (a['grad'] ?? '').compareTo(b['grad'] ?? '');
      if (byGrad != 0) return byGrad;
      return aVreme.compareTo(bVreme);
    });

    final selected = slots.first;
    _selectedGrad = selected['grad'] ?? _selectedGrad;
    _selectedVreme = V3TimeUtils.normalizeToHHmm(selected['vreme']);
  }

  // ─── Cache helpers ────────────────────────────────────────────────────────

  String _effectiveTime(Map<String, dynamic> row) {
    return ((row['polazak_at'] as String?) ?? '').trim();
  }

  bool _putnikPostoji(String putnikId) {
    final putnik = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    return putnik != null;
  }

  /// Vozač za termin iz trenutne dodele.
  V3Vozac? _getVozacZaTermin(String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final vozacId = V3StatusPolicy.sharedVozacIdForTermin(
      operativnaRows: rm.operativnaNedeljaCache.values,
      grad: grad,
      vreme: vreme,
      datumIso: _selectedDatumIso,
      vozacIdForRow: _vozacIdForOperativnaRow,
      isVisibleRow: (row) {
        final putnikId = row['created_by']?.toString() ?? '';
        return _putnikPostoji(putnikId) &&
            V3StatusPolicy.canAssign(
              status: row['status']?.toString(),
              otkazanoAt: row['otkazano_at'],
              pokupljenAt: row['pokupljen_at'],
            );
      },
      vremeKolona: 'polazak_at',
    );

    final resolvedVozacId = (vozacId ?? '').trim().isNotEmpty
        ? vozacId!.trim()
        : V3DodelaResolverService.resolveVozacIdForSlot(
            datumIso: _selectedDatumIso,
            grad: grad,
            vreme: vreme,
            activeVozacBySlotKey: _activeVozacBySlotKey,
          );

    if (resolvedVozacId.isNotEmpty) {
      return V3VozacService.getVozacById(resolvedVozacId);
    }
    return null;
  }

  /// Vozač za putnika iz trenutne dodele (bez fallback-a).
  V3Vozac? _getVozacZaPutnika(String putnikId, String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final vozacId = V3StatusPolicy.assignedVozacIdForPutnik(
      operativnaRows: rm.operativnaNedeljaCache.values,
      putnikId: putnikId,
      grad: grad,
      vreme: vreme,
      datumIso: _selectedDatumIso,
      vozacIdForRow: _vozacIdForOperativnaRow,
      isVisibleRow: (row) => V3StatusPolicy.canAssign(
        status: row['status']?.toString(),
        otkazanoAt: row['otkazano_at'],
        pokupljenAt: row['pokupljen_at'],
      ),
      vremeKolona: 'polazak_at',
    );
    if ((vozacId ?? '').isNotEmpty) {
      final vozac = V3VozacService.getVozacById(vozacId!);
      if (vozac != null) return vozac;
    }
    return null;
  }

  int _getPutnikCount(String grad, String vreme) {
    final targetDatum = _selectedDatumIso;
    final entries = V3OperativnaNedeljaService.getOperativnaNedeljaByDatum(targetDatum);
    return V3StatusPolicy.countOccupiedSeatsForSlot<V3OperativnaNedeljaEntry>(
      items: entries,
      grad: grad,
      vreme: vreme,
      gradOf: (entry) => entry.grad,
      vremeOf: (entry) => entry.polazakAt,
      seatsOf: (entry) => entry.brojMesta,
      statusOf: (entry) => entry.statusFinal,
      otkazanoAtOf: (entry) => entry.otkazanoAt,
    );
  }

  Color? _getVozacBoja(String grad, String vreme) {
    final v = _getVozacZaTermin(grad, vreme);
    return v != null ? V3CardColorPolicy.vozacColorOr(v.boja) : null;
  }

  // ─── DB operacije ─────────────────────────────────────────────────────────

  Future<void> _dodelijTermin(String grad, String vreme, V3Vozac vozac) async {
    try {
      final datum = _selectedDatumIso;
      final actorUuid = V3UuidUtils.normalizeUuid(
        V3VozacService.currentVozac?.id,
      );

      final assignedCount = await V3DodelaOrchestratorService.assignTerminDefault(
        operativnaRows: V3MasterRealtimeManager.instance.operativnaNedeljaCache.values,
        datumIso: datum,
        grad: grad,
        vreme: vreme,
        vozacId: vozac.id,
        updatedBy: actorUuid,
        includeRow: (row) {
          final putnikId = row['created_by']?.toString() ?? '';
          return _putnikPostoji(putnikId) &&
              V3StatusPolicy.canAssign(
                status: row['status']?.toString(),
                otkazanoAt: row['otkazano_at'],
                pokupljenAt: row['pokupljen_at'],
              );
        },
      );

      await _reloadTrenutnaDodelaMap();
      if (mounted) setState(() {});

      if (mounted) {
        V3AppSnackBar.success(
            context,
            '✅ ${vozac.imePrezime} → $grad $vreme ($datum)\n'
            '📋 $assignedCount putnika raspoređeno');
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _ukloniTermin(String grad, String vreme) async {
    try {
      await V3DodelaOrchestratorService.clearTerminDefault(
        operativnaRows: V3MasterRealtimeManager.instance.operativnaNedeljaCache.values,
        datumIso: _selectedDatumIso,
        grad: grad,
        vreme: vreme,
        includeRow: (row) {
          final putnikId = row['created_by']?.toString() ?? '';
          return _putnikPostoji(putnikId) &&
              V3StatusPolicy.canAssign(
                status: row['status']?.toString(),
                otkazanoAt: row['otkazano_at'],
                pokupljenAt: row['pokupljen_at'],
              );
        },
      );

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

      final assigned = await V3DodelaOrchestratorService.assignPutnikOverride(
        operativnaRows: V3MasterRealtimeManager.instance.operativnaNedeljaCache.values,
        datumIso: datum,
        putnikId: putnikId,
        grad: grad,
        vreme: vreme,
        vozacId: vozac.id,
        updatedBy: actorUuid,
        includeRow: (row) => V3StatusPolicy.canAssign(
          status: row['status']?.toString(),
          otkazanoAt: row['otkazano_at'],
          pokupljenAt: row['pokupljen_at'],
        ),
      );

      if (!assigned) {
        if (mounted) V3AppSnackBar.warning(context, '⚠️ Nema operativnog reda za izabranog putnika/termin');
        return;
      }

      await _reloadTrenutnaDodelaMap();
      if (mounted) setState(() {});

      if (mounted) V3AppSnackBar.success(context, '✅ ${vozac.imePrezime} → putnik ($datum)');
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _ukloniPutnikDodjelu(String putnikId, String grad, String vreme) async {
    try {
      await V3DodelaOrchestratorService.clearPutnikOverride(
        operativnaRows: V3MasterRealtimeManager.instance.operativnaNedeljaCache.values,
        datumIso: _selectedDatumIso,
        putnikId: putnikId,
        grad: grad,
        vreme: vreme,
        includeRow: (row) => V3StatusPolicy.canAssign(
          status: row['status']?.toString(),
          otkazanoAt: row['otkazano_at'],
          pokupljenAt: row['pokupljen_at'],
        ),
      );

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
                    color: V3CardColorPolicy.vozacColorOr(v.boja),
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
                    color: V3CardColorPolicy.vozacColorOr(v.boja),
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
      stream: V3MasterRealtimeManager.instance.v3StreamFromRevisions<List<V3OperativnaNedeljaEntry>>(
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
        final currentVozacId = V3VozacService.currentVozac?.id;

        // Zapisi za selektovani grad+vreme (datum je već filtriran stream-om)
        final zapisi = _selectedVreme.isNotEmpty
            ? (sviZapisi
                .where((z) => V3StatusPolicy.matchesSelectedSlot(
                      entryGrad: z.grad,
                      entryVreme: z.polazakAt,
                      grad: _selectedGrad,
                      vreme: _selectedVreme,
                    ))
                .toList()
              ..sort((a, b) {
                return V3StatusPolicy.compareEntriesForDisplay<V3OperativnaNedeljaEntry>(
                  a: a,
                  b: b,
                  currentVozacId: currentVozacId,
                  otkazanoAtOf: (entry) => entry.otkazanoAt,
                  pokupljenAtOf: (entry) => entry.pokupljenAt,
                  putnikIdOf: (entry) => entry.putnikId,
                  assignedVozacIdForEntry: (entry) {
                    final indiv = _getVozacZaPutnika(entry.putnikId, entry.grad ?? '', slotVreme(entry));
                    return indiv?.id;
                  },
                  putnikNameById: (putnikId) => V3PutnikService.getPutnikById(putnikId)?.imePrezime ?? '',
                );
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
                                              ? V3CardColorPolicy.vozacColorOr(indivVozac.boja)
                                              : (terminDodeljen
                                                  ? V3CardColorPolicy.vozacColorOr(vozacTermin.boja)
                                                  : null);

                                          final putnik = V3PutnikService.getPutnikById(z.putnikId) ??
                                              V3Putnik(
                                                id: z.putnikId,
                                                imePrezime: 'Nepoznat putnik',
                                                tipPutnika: 'dnevni',
                                              );
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: V3PutnikCard(
                                              putnik: putnik,
                                              entry: z,
                                              redniBroj: redniBroj,
                                              vozacBoja: vozacBoja,
                                              onDodeliVozaca: !V3StatusPolicy.canAssign(
                                                status: z.statusFinal,
                                                otkazanoAt: z.otkazanoAt,
                                                pokupljenAt: z.pokupljenAt,
                                              )
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
              return V3BottomNavBarSlotovi(
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
    final color = vozac != null ? V3CardColorPolicy.vozacColorOr(vozac.boja) : Colors.white24;
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
  final String selectedGrad;
  final String selectedVreme;
  final void Function(String, String) onChanged;
  final int Function(String, String) getCount;
  final int? Function(String, String) getKapacitet;

  const _NavBarProps({
    required this.selectedGrad,
    required this.selectedVreme,
    required this.onChanged,
    required this.getCount,
    required this.getKapacitet,
  });
}

// ─── Termin tile ──────────────────────────────────────────────────────────────
