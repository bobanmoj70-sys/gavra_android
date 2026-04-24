import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../globals.dart';
import '../models/v3_putnik.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_foreground_gps_service.dart';
import '../services/v3/v3_operativna_nedelja_service.dart';
import '../services/v3/v3_smart_navigation_service.dart';
import '../services/v3/v3_trenutna_dodela_service.dart';
import '../services/v3/v3_trenutna_dodela_slot_service.dart';
import '../services/v3/v3_vozac_lokacija_service.dart';
import '../services/v3/v3_vozac_service.dart';
import '../services/v3_biometric_service.dart';
import '../services/v3_theme_manager.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_card_color_policy.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_navigation_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_stream_utils.dart';
import '../utils/v3_telefon_helper.dart';
import '../utils/v3_time_utils.dart';
import '../widgets/v3_bottom_nav_bar_slotovi.dart';
import '../widgets/v3_live_clock_text.dart';
import '../widgets/v3_neradni_dani_banner.dart';
import '../widgets/v3_putnik_card.dart';
import '../widgets/v3_update_banner.dart';
import 'v3_welcome_screen.dart';

/// V3 Vozač Screen - prikazuje dodjeljene termine i putnike
/// iz cache-a građenog iz v3_operativna_nedelja.
///
/// Optimizacija rute koristi OSRM na ručni zahtev vozača.
class V3VozacScreen extends StatefulWidget {
  const V3VozacScreen({super.key});

  @override
  State<V3VozacScreen> createState() => _V3VozacScreenState();
}

class _V3VozacScreenState extends State<V3VozacScreen> {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _biometricPromptChoicePrefix = 'v3_biometric_prompt_choice_';

  DateTime _selectedDate = V3DanHelper.dateOnly(DateTime.now());
  String _selectedGrad = 'BC';
  String _selectedVreme = '';
  bool _isLoading = true;
  bool _isTracking = false;
  bool _isOptimizingRoute = false;
  bool _loadingDodela = false;
  RealtimeChannel? _trenutnaDodelaChannel;
  final Map<String, Map<String, int>> _optimizedOrderBySlotKey = <String, Map<String, int>>{};

  int? _lastRealtimeTick;

  /// Efektivni vozač
  dynamic get _efektivniVozac => V3VozacService.currentVozac;

  // Moji termini (izvor: v3_operativna_nedelja)
  List<Map<String, dynamic>> _mojiTermini = [];

  // Moji putnici (izvor: v3_operativna_nedelja)
  List<_PutnikEntry> _mojiPutnici = [];
  Set<String> _assignedOperativnaIds = <String>{};
  List<Map<String, String>> _assignedSlotRows = <Map<String, String>>[];

  int _timeToMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return -1;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
    return hour * 60 + minute;
  }

  bool _isGpsRowEligible(Map<String, dynamic> row) {
    return V3StatusPolicy.canAssign(
      status: row['status']?.toString(),
      otkazanoAt: row['otkazano_at'],
      pokupljenAt: row['pokupljen_at'],
    );
  }

  Future<void> _reloadTrenutnaDodelaForVozac() async {
    final vozac = _efektivniVozac;
    if (vozac == null) {
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
      return;
    }

    final vozacAuthId = (vozac.id?.toString() ?? '').trim();
    if (vozacAuthId.isEmpty) {
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
      return;
    }

    _loadingDodela = true;
    try {
      _assignedOperativnaIds = await V3TrenutnaDodelaService.loadActiveTerminIds(vozacId: vozacAuthId);
      _assignedSlotRows = await V3TrenutnaDodelaSlotService.loadActiveSlotsForVozac(vozacId: vozacAuthId);
    } catch (e) {
      debugPrint('[V3VozacScreen] _reloadTrenutnaDodelaForVozac error: $e');
      _assignedOperativnaIds = <String>{};
      _assignedSlotRows = <Map<String, String>>[];
    } finally {
      _loadingDodela = false;
    }
  }

  void _startTrenutnaDodelaRealtime() {
    final vozac = _efektivniVozac;
    final vozacAuthId = (vozac?.id?.toString() ?? '').trim();
    if (vozacAuthId.isEmpty) return;

    final existing = _trenutnaDodelaChannel;
    if (existing != null) {
      supabase.removeChannel(existing);
      _trenutnaDodelaChannel = null;
    }

    final channel = supabase.channel('v3_trenutna_dodela_vozac_$vozacAuthId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: V3TrenutnaDodelaService.tableName,
      callback: (payload) {
        final newVozacId = payload.newRecord[V3TrenutnaDodelaService.colVozacId]?.toString().trim() ?? '';
        final oldVozacId = payload.oldRecord[V3TrenutnaDodelaService.colVozacId]?.toString().trim() ?? '';
        if (newVozacId != vozacAuthId && oldVozacId != vozacAuthId) return;
        _refreshDodelaFromRealtime();
      },
    );
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: V3TrenutnaDodelaSlotService.tableName,
      callback: (payload) {
        final newVozacId = payload.newRecord[V3TrenutnaDodelaSlotService.colVozacId]?.toString().trim() ?? '';
        final oldVozacId = payload.oldRecord[V3TrenutnaDodelaSlotService.colVozacId]?.toString().trim() ?? '';
        if (newVozacId != vozacAuthId && oldVozacId != vozacAuthId) return;
        _refreshDodelaFromRealtime();
      },
    );
    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.channelError && error != null) {
        debugPrint('[V3VozacScreen] dodela realtime channelError: $error');
      }
      if (status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[V3VozacScreen] dodela realtime timedOut');
      }
    });

    _trenutnaDodelaChannel = channel;
  }

  Future<void> _refreshDodelaFromRealtime() async {
    if (!mounted) return;
    await _reloadTrenutnaDodelaForVozac();
    if (!mounted) return;
    _rebuild();
  }

  List<Map<String, dynamic>> _assignedOperativnaRows({
    String? datumIso,
    String? grad,
    String? vreme,
    bool onlyEligible = false,
  }) {
    final rm = V3MasterRealtimeManager.instance;
    final trazeniDatum = datumIso?.trim() ?? '';
    final trazeniGrad = grad?.trim().toUpperCase() ?? '';
    final trazenoVreme = V3TimeUtils.normalizeToHHmm(vreme);

    final rows = <Map<String, dynamic>>[];
    for (final operativnaId in _assignedOperativnaIds) {
      final raw = rm.operativnaNedeljaCache[operativnaId] ?? rm.operativnaAssignedCache[operativnaId];
      if (raw == null) continue;

      final row = Map<String, dynamic>.from(raw);
      row['vreme'] = row['vreme'] ?? row['polazak_at'];

      if (trazeniDatum.isNotEmpty) {
        final rowDatum = V3DanHelper.parseIsoDatePart(row['datum'] as String? ?? '');
        if (rowDatum != trazeniDatum) continue;
      }

      if (trazeniGrad.isNotEmpty) {
        final rowGrad = row['grad']?.toString().toUpperCase() ?? '';
        if (rowGrad != trazeniGrad) continue;
      }

      if (trazenoVreme.isNotEmpty) {
        final rowVreme = V3TimeUtils.normalizeToHHmm(row['vreme']?.toString());
        if (rowVreme != trazenoVreme) continue;
      }

      if (onlyEligible && !_isGpsRowEligible(row)) continue;
      rows.add(row);
    }

    return rows;
  }

  List<Map<String, dynamic>> _assignedSlotTermRows({
    String? datumIso,
    String? grad,
    String? vreme,
  }) {
    final trazeniDatum = (datumIso ?? '').trim();
    final trazeniGrad = (grad ?? '').trim().toUpperCase();
    final trazenoVreme = V3TimeUtils.normalizeToHHmm(vreme);

    final rows = <Map<String, dynamic>>[];
    for (final slot in _assignedSlotRows) {
      final slotDatum = (slot[V3TrenutnaDodelaSlotService.colDatum] ?? '').trim();
      final slotGrad = (slot[V3TrenutnaDodelaSlotService.colGrad] ?? '').trim().toUpperCase();
      final slotVreme = V3TimeUtils.normalizeToHHmm(slot[V3TrenutnaDodelaSlotService.colVreme]);

      if (slotDatum.isEmpty || slotGrad.isEmpty || slotVreme.isEmpty) continue;
      if (trazeniDatum.isNotEmpty && slotDatum != trazeniDatum) continue;
      if (trazeniGrad.isNotEmpty && slotGrad != trazeniGrad) continue;
      if (trazenoVreme.isNotEmpty && slotVreme != trazenoVreme) continue;

      rows.add(<String, dynamic>{
        'id': 'slot|$slotDatum|$slotGrad|$slotVreme',
        'datum': slotDatum,
        'grad': slotGrad,
        'vreme': slotVreme,
        'polazak_at': slotVreme,
      });
    }

    return rows;
  }

  bool _isExcludedFromOptimization(_PutnikEntry entry) {
    return !V3StatusPolicy.canAssign(
      status: entry.entry?.statusFinal,
      otkazanoAt: entry.entry?.otkazanoAt,
      pokupljenAt: entry.entry?.pokupljenAt,
    );
  }

  String _currentRouteSlotKey() {
    final vreme = V3TimeUtils.normalizeToHHmm(_selectedVreme);
    return '${_selectedDatumIso}|${_selectedGrad.toUpperCase()}|$vreme';
  }

  List<_PutnikEntry> _sortPutniciForDisplay(
    List<_PutnikEntry> putnici, {
    Map<String, int> optimizedOrderByPutnikId = const {},
  }) {
    final sorted = List<_PutnikEntry>.from(putnici);
    sorted.sort((a, b) {
      int sortRank(_PutnikEntry entry) {
        if (!V3StatusPolicy.countsAsOccupied(
          status: entry.entry?.statusFinal,
          otkazanoAt: entry.entry?.otkazanoAt,
        )) {
          return 3;
        }
        if (V3StatusPolicy.isTimestampSet(entry.entry?.pokupljenAt)) return 2;
        return 1;
      }

      final aRank = sortRank(a);
      final bRank = sortRank(b);

      if (aRank != bRank) {
        return aRank.compareTo(bRank);
      }

      if (aRank == 1 && optimizedOrderByPutnikId.isNotEmpty) {
        final aOrder = optimizedOrderByPutnikId[a.putnik.id];
        final bOrder = optimizedOrderByPutnikId[b.putnik.id];

        if (aOrder != null && bOrder != null && aOrder != bOrder) {
          return aOrder.compareTo(bOrder);
        }
        if (aOrder != null && bOrder == null) return -1;
        if (aOrder == null && bOrder != null) return 1;
      }

      return a.putnik.imePrezime.compareTo(b.putnik.imePrezime);
    });
    return sorted;
  }

  List<_PutnikEntry> _optimizacijaPutnici() {
    return _mojiPutnici.where((entry) => !_isExcludedFromOptimization(entry)).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = V3DanHelper.defaultWorkdayDate();
    _startTrenutnaDodelaRealtime();
    _initData();
  }

  @override
  void dispose() {
    V3StreamUtils.cancelSubscription('vozac_screen_realtime');
    V3StreamUtils.cancelSubscription('vozac_screen_gps');
    final channel = _trenutnaDodelaChannel;
    _trenutnaDodelaChannel = null;
    if (channel != null) {
      supabase.removeChannel(channel);
    }
    super.dispose();
  }

  Future<void> _initData() async {
    if (V3VozacService.currentVozac == null) {
      if (mounted) {
        V3NavigationUtils.pushAndRemoveUntil(context, const V3WelcomeScreen());
      }
      return;
    }

    final rm = V3MasterRealtimeManager.instance;
    if (rm.operativnaAssignedCache.isEmpty || rm.putniciCache.isEmpty) {
      try {
        await rm.initV3();
      } catch (_) {
        // Realtime manager već loguje detalje; ekran će prikazati šta je dostupno
      }
    }

    if (mounted) {
      await _reloadTrenutnaDodelaForVozac();
      _rebuild();
      V3StateUtils.safeSetState(this, () => _isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _rebuild();
      });
    }
  }

  void _rebuild() {
    final vozac = _efektivniVozac;
    if (vozac == null) return;
    final rm = V3MasterRealtimeManager.instance;

    String operativnaVreme(Map<String, dynamic> row) {
      return ((row['polazak_at'] as String?) ?? '');
    }

    final selectedVNorm = V3TimeUtils.normalizeToHHmm(_selectedVreme);

    // 1. Moji termini za ovaj datum (izvor dodele: v3_trenutna_dodela)
    final assignedRows = _assignedOperativnaRows(
      datumIso: _selectedDatumIso,
      onlyEligible: true,
    );

    final assignedSlotRows = _assignedSlotTermRows(
      datumIso: _selectedDatumIso,
    );

    final termsById = <String, Map<String, dynamic>>{};
    for (final row in assignedRows) {
      final entryId = row['id']?.toString() ?? '';
      if (entryId.isEmpty) continue;
      termsById[entryId] = row;
    }
    for (final row in assignedSlotRows) {
      final entryId = row['id']?.toString() ?? '';
      if (entryId.isEmpty) continue;
      termsById.putIfAbsent(entryId, () => row);
    }

    _mojiTermini = termsById.values.toList();

    // Ako selektovani grad/vreme ne odgovara nijednom terminu, auto-select i ponovi rebuild
    final terminPostoji = _mojiTermini.any((t) =>
        t['grad']?.toString().toUpperCase() == _selectedGrad &&
        V3TimeUtils.normalizeToHHmm(t['vreme']?.toString()) == selectedVNorm);

    if (!terminPostoji) {
      final stariGrad = _selectedGrad;
      final staroVreme = _selectedVreme;
      _selectClosestTermin();
      final terminPromenjen = _selectedGrad != stariGrad || _selectedVreme != staroVreme;
      if (terminPromenjen && _selectedVreme.isNotEmpty) {
        // Pronašao bliži termin — odmah ponovi rebuild sa novim vrednostima
        _rebuild();
        return;
      }
      // Nema termina za ovaj dan — prikaži prazno
      V3StateUtils.safeSetState(this, () => _mojiPutnici = []);
      return;
    }

    // 2. Putnici za ovaj dan/grad/vreme:
    //    Direktno iz izvedenog operativna cache-a, ali dodela isključivo preko v3_trenutna_dodela

    // Putnici iz operativna reda za assigned ID-jeve (putnik-level dodela dolazi iz v3_trenutna_dodela)
    final terminPutnici = _assignedOperativnaRows(
      datumIso: _selectedDatumIso,
      grad: _selectedGrad,
      vreme: selectedVNorm,
      onlyEligible: true,
    ).where((r) => r['created_by'] != null);

    // Redovi bez duplikata po operativna ID
    final allSelectedRowsById = <String, Map<String, dynamic>>{};
    for (final row in terminPutnici) {
      final entryId = row['id']?.toString();
      if (entryId == null || entryId.isEmpty) continue;
      allSelectedRowsById.putIfAbsent(entryId, () => row);
    }

    // 3. Za svaki red izgradimo _PutnikEntry iz operativna_nedelja
    final putnici = <_PutnikEntry>[];
    for (final row in allSelectedRowsById.values) {
      final putnikId = row['created_by']?.toString();
      final putnikData = putnikId != null ? rm.putniciCache[putnikId] : null;
      if (putnikData == null) continue;

      final entryId = row['id']?.toString() ?? '';
      final V3Putnik putnik = V3Putnik.fromJson(putnikData);

      // Pronađi entry iz operativna_nedelja za ovaj red
      V3OperativnaNedeljaEntry? entry;
      Map<String, dynamic>? matchedEntryData;
      if (entryId.isNotEmpty) {
        matchedEntryData = rm.operativnaNedeljaCache[entryId];
      }

      if (matchedEntryData == null && putnikId != null && putnikId.isNotEmpty) {
        DateTime? bestUpdatedAt;
        for (final r in rm.operativnaNedeljaCache.values) {
          if (!V3StatusPolicy.countsAsOccupied(
            status: r['status']?.toString(),
            otkazanoAt: r['otkazano_at'],
          )) {
            continue;
          }
          if (r['created_by']?.toString() != putnikId) continue;
          if (V3DanHelper.parseIsoDatePart(r['datum'] as String? ?? '') != _selectedDatumIso) continue;
          if (r['grad']?.toString().toUpperCase() != _selectedGrad) continue;
          if (V3TimeUtils.normalizeToHHmm(operativnaVreme(r)) != selectedVNorm) continue;

          final updatedAtRaw = r['updated_at']?.toString();
          final updatedAt = updatedAtRaw != null ? DateTime.tryParse(updatedAtRaw) : null;
          if (matchedEntryData == null) {
            matchedEntryData = r;
            bestUpdatedAt = updatedAt;
            continue;
          }
          if (updatedAt != null && (bestUpdatedAt == null || updatedAt.isAfter(bestUpdatedAt))) {
            matchedEntryData = r;
            bestUpdatedAt = updatedAt;
          }
        }
      }

      if (matchedEntryData != null) {
        entry = V3OperativnaNedeljaEntry.fromJson(matchedEntryData);
      }

      putnici.add(
        _PutnikEntry(
          putnik: putnik,
          entry: entry,
        ),
      );
    }

    final effectiveOptimizedOrder = _optimizedOrderBySlotKey[_currentRouteSlotKey()] ?? const <String, int>{};
    V3StateUtils.safeSetState(this, () {
      _mojiPutnici = _sortPutniciForDisplay(
        putnici,
        optimizedOrderByPutnikId: effectiveOptimizedOrder,
      );
    });
  }

  void _selectClosestTermin() {
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    String? bestVreme;
    String? bestGrad;
    int minDiff = 9999;

    // Kandidati: samo termini (putnici se izvlače automatski iz operativna_nedelja)
    final kandidati = <Map<String, dynamic>>[
      ..._mojiTermini,
    ];

    for (final t in kandidati) {
      final grad = t['grad']?.toString().toUpperCase() ?? '';
      final vreme = t['vreme']?.toString() ?? '';
      if (vreme.isEmpty) continue;
      final tp = vreme.split(':');
      if (tp.length < 2) continue;
      final mins = (int.tryParse(tp[0]) ?? 0) * 60 + (int.tryParse(tp[1]) ?? 0);
      final diff = (mins - current).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestVreme = V3DanHelper.formatVreme(int.tryParse(tp[0]) ?? 0, int.tryParse(tp[1]) ?? 0);
        bestGrad = grad;
      }
    }
    if (bestVreme != null && bestGrad != null) {
      _selectedVreme = bestVreme;
      _selectedGrad = bestGrad;
    }
  }

  String get _selectedDay => V3DanHelper.fullName(_selectedDate);

  String get _selectedDatumIso {
    return V3DanHelper.toIsoDate(_selectedDate);
  }

  String? get _neradanDanRazlog => getNeradanDanRazlog(datumIso: _selectedDatumIso, grad: _selectedGrad);

  void _onPolazakChanged(String grad, String vreme) {
    setState(() {
      _selectedGrad = grad;
      _selectedVreme = vreme;
    });
    _rebuild();
  }

  void _onDaySelected(String day) {
    final vozac = _efektivniVozac;
    if (vozac == null) return;

    final dayAbbr = V3DanHelper.workdayAbbrFromFullName(day);
    final dayIso = V3DanHelper.datumIsoZaDanAbbrUTekucojSedmici(
      dayAbbr,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );
    final parsedDayDate = DateTime.tryParse(dayIso);
    if (parsedDayDate == null) return;
    final selectedDayDate = V3DanHelper.dateOnly(parsedDayDate);
    final dayTerms = [
      ..._assignedOperativnaRows(
        datumIso: dayIso,
        onlyEligible: true,
      ),
      ..._assignedSlotTermRows(
        datumIso: dayIso,
      ),
    ];

    final currentVremeNorm = V3TimeUtils.normalizeToHHmm(_selectedVreme);
    final hasCurrentSelection = dayTerms.any(
      (row) =>
          (row['grad']?.toString().toUpperCase() ?? '') == _selectedGrad &&
          V3TimeUtils.normalizeToHHmm(row['vreme']?.toString()) == currentVremeNorm,
    );

    Map<String, dynamic>? bestTerm;
    if (dayTerms.isNotEmpty && !hasCurrentSelection) {
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;
      dayTerms.sort((a, b) {
        final aTime = V3TimeUtils.normalizeToHHmm(a['vreme']?.toString());
        final bTime = V3TimeUtils.normalizeToHHmm(b['vreme']?.toString());
        final aDiff = _timeToMinutes(aTime) < 0 ? 99999 : (_timeToMinutes(aTime) - nowMinutes).abs();
        final bDiff = _timeToMinutes(bTime) < 0 ? 99999 : (_timeToMinutes(bTime) - nowMinutes).abs();
        if (aDiff != bDiff) return aDiff.compareTo(bDiff);
        final ga = a['grad']?.toString().toUpperCase() ?? '';
        final gb = b['grad']?.toString().toUpperCase() ?? '';
        final byGrad = ga.compareTo(gb);
        if (byGrad != 0) return byGrad;
        return aTime.compareTo(bTime);
      });
      bestTerm = dayTerms.first;
    }

    if (!mounted) return;
    setState(() {
      _selectedDate = selectedDayDate;

      if (bestTerm != null) {
        _selectedGrad = bestTerm['grad']?.toString().toUpperCase() ?? _selectedGrad;
        _selectedVreme = V3TimeUtils.normalizeToHHmm(bestTerm['vreme']?.toString());
      } else if (dayTerms.isEmpty) {
        _selectedVreme = '';
      }

      if (dayTerms.isNotEmpty && _selectedVreme.isEmpty) {
        final firstTerm = dayTerms.first;
        _selectedGrad = firstTerm['grad']?.toString().toUpperCase() ?? _selectedGrad;
        _selectedVreme = V3TimeUtils.normalizeToHHmm(firstTerm['vreme']?.toString());
      }
    });

    _rebuild();
  }

  Future<void> _openMapa() async {
    await V3TelefonHelper.otvoriHereWeGoAppOnly(this, context);
  }

  Future<void> _logout() async {
    final ok = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'Logout',
      message: 'Da li ste sigurni da želite da se odjavite?',
      confirmText: 'Logout',
      cancelText: 'Otkaži',
      isDangerous: true,
    );
    if (ok == true && mounted) {
      final phoneRaw = V3VozacService.currentVozac?.telefon1 ?? '';
      final normalizedPhone = V3ClosedAuthService.normalizePhone(phoneRaw);
      if (normalizedPhone.isNotEmpty) {
        await _secureStorage.delete(key: '$_biometricPromptChoicePrefix$normalizedPhone');
      }

      await V3BiometricService().clearCredentials();
      V3VozacService.currentVozac = null;
      await V3ClosedAuthService.clearManualSmsVozacPhone();
      await V3ClosedAuthService.clearManualSmsPutnikPhone();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const V3WelcomeScreen()),
        (r) => false,
      );
    }
  }

  int _getPutnikCount(String grad, String vreme) {
    final rm = V3MasterRealtimeManager.instance;
    final vozac = V3VozacService.currentVozac;
    if (vozac == null) return 0;

    final vremeNorm = V3TimeUtils.normalizeToHHmm(vreme);
    final gradUp = grad.toUpperCase();

    bool hasActivePutnik(Map<String, dynamic> row) {
      final putnikId = row['created_by']?.toString();
      if (putnikId == null || putnikId.isEmpty) return false;
      final putnik = rm.putniciCache[putnikId];
      return putnik != null;
    }

    // Broji sva mesta za assigned redove (putnik-level dodela: v3_trenutna_dodela)
    final rows = _assignedOperativnaRows(
      datumIso: _selectedDatumIso,
      grad: gradUp,
      vreme: vremeNorm,
    ).where((r) => hasActivePutnik(r));

    return V3StatusPolicy.countOccupiedSeatsForSlot<Map<String, dynamic>>(
      items: rows,
      grad: gradUp,
      vreme: vremeNorm,
      gradOf: (row) => row['grad']?.toString(),
      vremeOf: (row) => row['vreme']?.toString() ?? row['polazak_at']?.toString(),
      seatsOf: (row) => V3StatusPolicy.parseSeats(row['broj_mesta']),
      statusOf: (row) => row['status']?.toString(),
      otkazanoAtOf: (row) => row['otkazano_at'],
    );
  }

  Future<void> _toggleTracking() async {
    final vozac = _efektivniVozac;
    if (vozac == null) return;

    if (!_isTracking) {
      final canContinue = await _ensureDriverLocationDisclosure();
      if (!canContinue) return;

      // 1. START FOREGROUND GPS TRACKING SA PERSISTENT NOTIFICATION
      V3StateUtils.safeSetState(this, () => _isTracking = true);

      try {
        // Pokreni foreground GPS service sa notification
        final success = await V3ForegroundGpsService.startTracking(
          vozacId: vozac.id,
          vozacIme: vozac.imePrezime ?? 'Vozač',
          polazakVreme: '$_selectedGrad $_selectedVreme',
          putnici: _optimizacijaPutnici().map((entry) => entry.putnik).toList(),
          grad: _selectedGrad,
        );

        if (success) {
          await V3ForegroundGpsService.syncTrackingStatus(
            vozacId: vozac.id,
            grad: _selectedGrad,
            polazakVreme: _selectedVreme,
            gpsStatus: 'tracking',
            datumIso: _selectedDatumIso,
          );

          if (_mojiPutnici.isNotEmpty) {
            await _optimizujRutu();
          }

          if (mounted) {
            V3AppSnackBar.success(
                context, '📍 GPS tracking pokrenut sa persistent notification! Putnici dobijaju realtime lokaciju.');
          }
        } else {
          V3StateUtils.safeSetState(this, () => _isTracking = false);
          if (mounted) {
            V3AppSnackBar.error(context, '❌ Greška pri pokretanju GPS trackinga. Provjerite dozvole u Settings.');
          }
        }
      } catch (e) {
        V3StateUtils.safeSetState(this, () => _isTracking = false);
        if (mounted) {
          V3AppSnackBar.error(context, '❌ Greška pri pokretanju GPS trackinga: $e');
        }
      }
    } else {
      // 2. STOP FOREGROUND GPS TRACKING
      V3StateUtils.safeSetState(this, () => _isTracking = false);

      // Zaustavi foreground service i notification
      await V3ForegroundGpsService.stopTracking();
      await V3ForegroundGpsService.syncTrackingStatus(
        vozacId: vozac.id,
        grad: _selectedGrad,
        polazakVreme: _selectedVreme,
        gpsStatus: 'pending',
        datumIso: _selectedDatumIso,
      );

      if (mounted) {
        V3AppSnackBar.warning(context, '⚠️ GPS tracking zaustavljen - notification uklonjena');
      }
    }
  }

  Future<bool> _ensureDriverLocationDisclosure() async {
    final locationWhenInUse = await Permission.location.status;

    if (locationWhenInUse.isGranted) {
      return true;
    }

    final requested = await Permission.location.request();
    if (requested.isGranted) {
      return true;
    }

    if (mounted) {
      V3AppSnackBar.warning(
        context,
        '⚠️ GPS dozvola nije odobrena. Uključite dozvolu u Settings.',
      );
    }
    return false;
  }

  Future<void> _optimizujRutu({
    bool silent = false,
  }) async {
    final putniciZaOptimizaciju = _optimizacijaPutnici();
    if (putniciZaOptimizaciju.isEmpty) return;

    if (_isOptimizingRoute) return;

    final vozac = V3VozacService.currentVozac;
    if (vozac == null) return;

    _isOptimizingRoute = true;

    try {
      final data = _buildOptimizationData(putniciZaOptimizaciju);

      final driverPosition = await _resolveDriverPositionForOptimization(
        vozacId: vozac.id,
        silent: silent,
      );
      if (driverPosition == null) return;

      final res = await _optimizeRouteWithOsrm(
        data: data,
        driverLat: driverPosition['lat']!,
        driverLng: driverPosition['lng']!,
      );

      if (res.success && res.optimizedData != null) {
        final optimizedOrder = <String, int>{};
        final optimizedData = res.optimizedData!;
        for (var index = 0; index < optimizedData.length; index++) {
          final item = optimizedData[index];
          final putnikObj = item['putnik'];
          String? putnikId;

          if (putnikObj is V3Putnik) {
            putnikId = putnikObj.id;
          } else if (putnikObj is Map<String, dynamic>) {
            putnikId = putnikObj['id']?.toString();
          }

          if (putnikId != null && putnikId.isNotEmpty) {
            optimizedOrder[putnikId] = index + 1;
          }
        }

        if (optimizedOrder.isNotEmpty) {
          final routeSlotKey = _currentRouteSlotKey();
          V3StateUtils.safeSetState(this, () {
            _optimizedOrderBySlotKey[routeSlotKey] = optimizedOrder;
            _mojiPutnici = _sortPutniciForDisplay(
              _mojiPutnici,
              optimizedOrderByPutnikId: optimizedOrder,
            );
          });
        }

        if (!silent && mounted) {
          V3AppSnackBar.success(context, res.message);
        }
      } else if (!silent && mounted) {
        V3AppSnackBar.warning(context, res.message);
      }
    } finally {
      _isOptimizingRoute = false;
    }
  }

  List<Map<String, dynamic>> _buildOptimizationData(List<_PutnikEntry> putnici) {
    return putnici.map((entry) => {'putnik': entry.putnik, 'entry': entry.entry}).toList();
  }

  Future<Map<String, double>?> _resolveDriverPositionForOptimization({
    required String vozacId,
    required bool silent,
  }) async {
    final gpsPosition = await _getCurrentDriverPosition(vozacId);
    final driverLat = gpsPosition?['lat'] as double?;
    final driverLng = gpsPosition?['lng'] as double?;

    if (driverLat == null || driverLng == null) {
      if (!silent && mounted) {
        V3AppSnackBar.warning(context, 'OSRM optimizacija zahteva aktivan GPS vozača.');
      }
      return null;
    }

    return {
      'lat': driverLat,
      'lng': driverLng,
    };
  }

  Future<V3NavigationResult> _optimizeRouteWithOsrm({
    required List<Map<String, dynamic>> data,
    required double driverLat,
    required double driverLng,
  }) {
    return V3SmartNavigationService.optimizeV3Route(
      data: data,
      fromCity: _selectedGrad,
      driverLat: driverLat,
      driverLng: driverLng,
    );
  }

  /// Dobija trenutnu GPS poziciju vozača iz baze podataka
  Future<Map<String, dynamic>?> _getCurrentDriverPosition(String vozacId) async {
    try {
      final response = V3VozacLokacijaService.getVozacLokacijaSync(vozacId, onlyActive: true);

      final lat = (response?['lat'] as num?)?.toDouble() ?? double.tryParse(response?['lat']?.toString() ?? '');
      final lng = (response?['lng'] as num?)?.toDouble() ?? double.tryParse(response?['lng']?.toString() ?? '');

      if (response != null && lat != null && lng != null) {
        return {
          'lat': lat,
          'lng': lng,
          'updated_at': response['updated_at'],
        };
      }
    } catch (e) {
      debugPrint('[V3VozacScreen] _getCurrentDriverPosition error: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vozac = V3VozacService.currentVozac;

    if (_isLoading) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: V3ContainerUtils.backgroundContainer(
            gradient: V3ThemeManager().currentGradient,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      );
    }

    // Termini za BottomNavBar — iz assigned ID-jeva + slot rezervacija
    final rm = V3MasterRealtimeManager.instance;
    String normV(String? v) {
      if (v == null || v.isEmpty) return '';
      final p = v.split(':');
      if (p.length >= 2) {
        final hour = int.tryParse(p[0]) ?? 0;
        final minute = int.tryParse(p[1]) ?? 0;
        return V3DanHelper.formatVreme(hour, minute);
      }
      return v;
    }

    final bcVremenaSet = <String>{};
    final vsVremenaSet = <String>{};
    for (final t in _mojiTermini) {
      final g = t['grad']?.toString().toUpperCase() ?? '';
      final v = normV(t['vreme']?.toString());
      if (v.isEmpty) continue;
      if (g == 'BC') bcVremenaSet.add(v);
      if (g == 'VS') vsVremenaSet.add(v);
    }
    for (final r in _assignedOperativnaRows(datumIso: _selectedDatumIso, onlyEligible: true)) {
      final g = r['grad']?.toString().toUpperCase() ?? '';
      final v = normV(r['vreme']?.toString());
      if (v.isEmpty) continue;
      if (g == 'BC') bcVremenaSet.add(v);
      if (g == 'VS') vsVremenaSet.add(v);
    }
    final bcVremenaToShow = bcVremenaSet.toList()..sort();
    final vsVremenaToShow = vsVremenaSet.toList()..sort();
    final textScaleFactor = MediaQuery.textScalerOf(context).scale(1.0);
    final headerScaleExtra = (textScaleFactor - 1.0).clamp(0.0, 0.7).toDouble();
    final appBarHeight = 104 + (headerScaleExtra * 18);
    final appBarButtonHeight = 30 + (headerScaleExtra * 6);
    final weekRange = V3DanHelper.schedulingWeekRange();
    final ponedeljak = weekRange.start;
    final petak = weekRange.end;
    final aktivnaSedmica =
        'Aktivna sedmica: ${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')} - ${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}';

    return StreamBuilder<int>(
      stream: rm.v3StreamFromCache<int>(
        tables: const ['v3_operativna_nedelja', 'v3_auth', 'v3_adrese', 'v3_kapacitet_slots', 'v3_app_settings'],
        build: () => DateTime.now().microsecondsSinceEpoch,
      ),
      builder: (context, snapshot) {
        final tick = snapshot.data;
        if (tick != null && tick != _lastRealtimeTick) {
          _lastRealtimeTick = tick;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _rebuild();
          });
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: V3ContainerUtils.backgroundContainer(
            gradient: V3ThemeManager().currentGradient,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(appBarHeight),
                child: V3ContainerUtils.styledContainer(
                  backgroundColor: Theme.of(context).glassContainer,
                  border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(25),
                    bottomRight: Radius.circular(25),
                  ),
                  padding: EdgeInsets.zero,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            aktivnaSedmica,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 3),
                          // ── Red 1: Datum | Dan (V2 digitalni prikaz) ──
                          _buildDigitalDateDisplay(context, vozac),
                          const SizedBox(height: 6),
                          // ── Red 2: Kompaktni gumbi (V2 stil h=30) ──
                          Row(
                            children: [
                              // START / STOP
                              Expanded(
                                flex: 2,
                                child: _buildAppBarBtn(
                                  context: context,
                                  label: _isTracking ? 'STOP' : 'START',
                                  color: _isTracking ? Colors.red : Colors.green,
                                  height: appBarButtonHeight,
                                  onTap: _toggleTracking,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // MAPA
                              Expanded(
                                flex: 2,
                                child: _buildAppBarBtn(
                                  context: context,
                                  label: 'MAPA',
                                  color: Colors.blue,
                                  height: appBarButtonHeight,
                                  onTap: _openMapa,
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Dan picker
                              Expanded(
                                flex: 2,
                                child: _buildDanPickerBtn(context, height: appBarButtonHeight),
                              ),
                              const SizedBox(width: 4),
                              // ⚙️ Popup meni — tema + logout
                              PopupMenuButton<String>(
                                onSelected: (val) async {
                                  if (val == 'tema') {
                                    await V3ThemeManager().nextTheme();
                                    V3StateUtils.safeSetState(this, () {});
                                    if (!mounted) return;
                                    V3AppSnackBar.info(context, '🎨 Tema promenjena');
                                  } else if (val == 'logout') {
                                    _logout();
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'tema',
                                    child: Row(children: [
                                      Icon(Icons.palette, color: Colors.purpleAccent),
                                      SizedBox(width: 8),
                                      Text('Promeni temu'),
                                    ]),
                                  ),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'logout',
                                    child: Row(children: [
                                      Icon(Icons.logout, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Logout'),
                                    ]),
                                  ),
                                ],
                                padding: EdgeInsets.zero,
                                child: V3ContainerUtils.iconContainer(
                                  width: V3ContainerUtils.responsiveHeight(context, 30),
                                  height: V3ContainerUtils.responsiveHeight(context, 30),
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  borderRadiusGeometry: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.more_vert, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottomNavigationBar: ValueListenableBuilder<String>(
                valueListenable: navBarTypeNotifier,
                builder: (context, navType, _) {
                  final neradanRazlog = _neradanDanRazlog;
                  if (neradanRazlog != null) {
                    return SafeArea(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.7)),
                        ),
                        child: Text(
                          '⛔ Slotovi zaključani za $_selectedDay. Razlog: $neradanRazlog',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  int? getKapacitet(String grad, String vreme) {
                    final datum = DateTime.tryParse(_selectedDatumIso) ?? DateTime.now();
                    return V3OperativnaNedeljaService.getKapacitetVozila(grad, vreme, datum);
                  }

                  return V3BottomNavBarSlotovi(
                    selectedGrad: _selectedGrad,
                    selectedVreme: _selectedVreme,
                    onPolazakChanged: _onPolazakChanged,
                    getPutnikCount: _getPutnikCount,
                    getKapacitet: getKapacitet,
                    bcVremena: bcVremenaToShow,
                    vsVremena: vsVremenaToShow,
                  );
                },
              ),
              body: _buildBody(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    final vozacBoja = _getVozacBojaRaw(_efektivniVozac);
    final redniBrojevi = <int>[];
    var tekuciRedniBroj = 1;
    for (final putnikEntry in _mojiPutnici) {
      redniBrojevi.add(tekuciRedniBroj);
      tekuciRedniBroj += putnikEntry.entry?.brojMesta ?? 1;
    }

    return Column(
      children: [
        const V3UpdateBanner(),
        Expanded(
          child: ValueListenableBuilder<List<Map<String, String>>>(
            valueListenable: neradniDaniNotifier,
            builder: (context, rules, _) {
              final weekRange = V3DanHelper.schedulingWeekRange();
              final today = V3DanHelper.dateOnly(DateTime.now());
              final hasNeradni = rules.any((rule) {
                final dateIso = V3DanHelper.parseIsoDatePart(rule['date'] ?? '');
                final date = DateTime.tryParse(dateIso);
                if (date == null) return false;
                final onlyDate = V3DanHelper.dateOnly(date);
                if (onlyDate.isBefore(today)) return false;
                return !onlyDate.isBefore(weekRange.start) && !onlyDate.isAfter(weekRange.end);
              });

              return Column(
                children: [
                  if (hasNeradni)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: V3NeradniDaniBanner(),
                    ),
                  Expanded(
                    child: _mojiPutnici.isEmpty
                        ? Center(
                            child: V3ContainerUtils.styledContainer(
                              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              padding: const EdgeInsets.all(20),
                              backgroundColor: Theme.of(context).glassContainer,
                              border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                              borderRadius: BorderRadius.circular(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inbox, color: Colors.white54, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Nema putnika za $_selectedGrad $_selectedVreme',
                                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 4, bottom: 16),
                            itemCount: _mojiPutnici.length,
                            itemBuilder: (context, index) {
                              final pz = _mojiPutnici[index];
                              return V3PutnikCard(
                                putnik: pz.putnik,
                                entry: pz.entry,
                                redniBroj: redniBrojevi[index],
                                vozacBoja: vozacBoja,
                                onChanged: _rebuild,
                                isExcludedFromOptimization: _isExcludedFromOptimization(pz),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ── V2 stil: digitalni datum prikaz ──
  Widget _buildDigitalDateDisplay(BuildContext context, dynamic vozac) {
    final selectedDate = _selectedDate;
    final dayName = _selectedDay.trim().toUpperCase();
    final dateStr = DateFormat('dd.MM.yy').format(selectedDate);
    final vozacBoja = _getVozacBojaRaw(vozac);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        Text(
          dayName,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: vozacBoja,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
        V3LiveClockText(
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onPrimary,
            shadows: const [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
          ),
        ),
      ],
    );
  }

  // ── Kompaktni AppBar dugme (label, h=30) ──
  Widget _buildAppBarBtn({
    required BuildContext context,
    required String label,
    required Color color,
    required double height,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: V3ContainerUtils.styledContainer(
        height: height,
        backgroundColor: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        padding: EdgeInsets.zero,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ── Dan picker dugme (AppBar stil) ──
  Widget _buildDanPickerBtn(BuildContext context, {required double height}) {
    return InkWell(
      onTap: _showDanDialog,
      borderRadius: BorderRadius.circular(8),
      child: V3ContainerUtils.styledContainer(
        height: height,
        backgroundColor: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
        padding: EdgeInsets.zero,
        child: Center(
          child: Text(
            _selectedDay.substring(0, 3).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _showDanDialog() {
    V3DialogHelper.showDialogBuilder<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Izaberi dan'),
        children: V3DanHelper.workdayNames.map((dan) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, dan),
            child: Text(dan, style: TextStyle(fontWeight: dan == _selectedDay ? FontWeight.bold : FontWeight.normal)),
          );
        }).toList(),
      ),
    ).then((dan) {
      if (dan != null && mounted) {
        _onDaySelected(dan);
      }
    });
  }

  // Puna boja vozača (bez alpha skaliranja) — za tekst/border
  Color _getVozacBojaRaw(dynamic v3Vozac) {
    final hex = v3Vozac?.boja?.toString();
    return V3CardColorPolicy.parseHexColor(hex, fallback: Colors.white);
  }
}

/// Helper klasa — putnik + njegov operativni entry
class _PutnikEntry {
  final V3Putnik putnik;
  final V3OperativnaNedeljaEntry? entry;
  const _PutnikEntry({required this.putnik, this.entry});
}
