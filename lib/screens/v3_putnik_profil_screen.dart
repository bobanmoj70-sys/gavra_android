import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../globals.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_closed_auth_service.dart';
import '../services/v3/v3_firebase_sms_service.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3/v3_putnik_statistika_service.dart';
import '../services/v3/v3_weather_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../services/v3_biometric_service.dart';
import '../services/v3_theme_manager.dart';
import '../utils/v3_app_messages.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_audit_korisnik.dart';
import '../utils/v3_button_utils.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dialog_helper.dart';
import '../utils/v3_error_utils.dart';
import '../utils/v3_state_utils.dart';
import '../utils/v3_status_filters.dart';
import '../utils/v3_status_presentation.dart';
import '../utils/v3_stream_utils.dart';
import '../utils/v3_string_utils.dart';
import '../utils/v3_style_helper.dart';
import '../widgets/v3_live_clock_text.dart';
import '../widgets/v3_neradni_dani_banner.dart';
import '../widgets/v3_update_banner.dart';
import '../widgets/v3_vozac_status_widget.dart';
import 'v3_putnik_statistika_screen.dart';
import 'v3_welcome_screen.dart';

class V3PutnikProfilScreen extends StatefulWidget {
  final Map<String, dynamic> putnikData;
  const V3PutnikProfilScreen({super.key, required this.putnikData});
  @override
  State<V3PutnikProfilScreen> createState() => _V3PutnikProfilScreenState();
}

class _V3PutnikProfilScreenState extends State<V3PutnikProfilScreen> with WidgetsBindingObserver {
  late Map<String, dynamic> _putnikData;
  Map<String, String> _activeVozacByTerminId = const {};
  PermissionStatus _notifStatus = PermissionStatus.granted;
  // Operativni termini po danu
  // key = dan kratica npr 'pon', value = lista termina (BC i VS)
  final Map<String, List<_ZahtevInfo>> _rasporedMap = {};
  Map<String, V3WeatherSnapshot> _weatherByGrad = const {};
  Timer? _weatherTimer;

  static final RegExp _timeFormat = RegExp(r'^\d{2}:\d{2}$');

  int _statusPriorityForCell(String status) {
    switch (status) {
      case 'odobreno':
        return 4;
      case 'obrada':
        return 3;
      case 'alternativa':
        return 2;
      case 'otkazano':
        return 1;
      default:
        return 0;
    }
  }

  String? _normalizeValidTime(String? value) {
    if (value == null) return null;
    final normalized = V3StringUtils.safeSubstringTime(value).trim();
    if (normalized.isEmpty) return null;
    if (!_timeFormat.hasMatch(normalized)) return null;
    return normalized;
  }

  String _formatNedeljaOpsegLabel() {
    final anchor = V3DanHelper.schedulingWeekAnchor();
    final ponedeljak = V3DanHelper.datumZaDanAbbrUTekucojSedmici('pon', anchor: anchor);
    final petak = V3DanHelper.datumZaDanAbbrUTekucojSedmici('pet', anchor: anchor);
    final od = '${ponedeljak.day.toString().padLeft(2, '0')}.${ponedeljak.month.toString().padLeft(2, '0')}.';
    final doDatuma = '${petak.day.toString().padLeft(2, '0')}.${petak.month.toString().padLeft(2, '0')}.';
    return '$od - $doDatuma';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _putnikData = Map<String, dynamic>.from(widget.putnikData);
    _checkNotifPermission();
    _refresh();
    _refreshWeather(forceRefresh: true);
    _weatherTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted) _refreshWeather();
    });
    // Pratimo promjene cache-a
    V3StreamUtils.subscribe<int>(
      key: 'putnik_profil_cache',
      stream: V3MasterRealtimeManager.instance
          .tablesRevisionStream(const ['v3_auth', 'v3_zahtevi', 'v3_operativna_nedelja']),
      onData: (_) {
        if (mounted) _refresh();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    V3StreamUtils.cancelSubscription('putnik_profil_cache');
    _weatherTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotifPermission();
      _refreshWeather();
    }
  }

  Future<void> _refreshWeather({bool forceRefresh = false}) async {
    final snapshots = await V3WeatherService.fetchBcVs(forceRefresh: forceRefresh);
    if (!mounted || snapshots.isEmpty) return;
    V3StateUtils.safeSetState(this, () => _weatherByGrad = snapshots);
  }

  Future<void> _checkNotifPermission() async {
    final status = await Permission.notification.status;
    V3StateUtils.safeSetState(this, () => _notifStatus = status);
  }

  Future<void> _requestNotifPermission() async {
    final status = await Permission.notification.request();
    V3StateUtils.safeSetState(this, () => _notifStatus = status);
    if (status.isPermanentlyDenied) await openAppSettings();
  }

  void _refresh() {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;
    _reloadTrenutnaDodelaForPutnik(putnikId);
    // Osvježi putnik iz cache-a
    final cached = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    if (cached != null) _putnikData = Map<String, dynamic>.from(cached);
    // Raspored po danima iz v3_operativna_nedelja kao jedinog izvora istine za READ
    final dani = V3DanHelper.workdayAbbrs.toList(); // pon-pet (radni dani)
    final anchor = V3DanHelper.schedulingWeekAnchor();
    final rm = V3MasterRealtimeManager.instance;
    final newMap = <String, List<_ZahtevInfo>>{};
    for (final dan in dani) {
      final datumIso = V3DanHelper.datumIsoZaDanAbbrUTekucojSedmici(dan, anchor: anchor);
      final infos = <_ZahtevInfo>[];

      for (final grad in const ['BC', 'VS']) {
        final opRows = rm.operativnaNedeljaCache.values.where((e) {
          final status = V3StatusFilters.normalizeStatus(V3StatusFilters.deriveOperativnaStatus(e));
          return (e['created_by']?.toString() ?? '') == putnikId &&
              (e['datum'] as String? ?? '').startsWith(datumIso) &&
              (e['grad']?.toString().toUpperCase() ?? '') == grad &&
              !V3StatusFilters.isCanceledOrRejected(status);
        }).toList();

        if (opRows.isEmpty) {
          final pendingRows = rm.zahteviCache.values.where((z) {
            final status = V3StatusFilters.normalizeStatus(z['status']?.toString());
            return (z['created_by']?.toString() ?? '') == putnikId &&
                (z['datum'] as String? ?? '').startsWith(datumIso) &&
                (z['grad']?.toString().toUpperCase() ?? '') == grad &&
                V3StatusFilters.isPending(status);
          }).toList();

          if (pendingRows.isEmpty) continue;

          pendingRows.sort((a, b) {
            final aTs = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTs = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTs.compareTo(aTs);
          });

          final pending = pendingRows.first;
          final trazeniVreme = _normalizeValidTime(pending['trazeni_polazak_at']?.toString()) ?? '—';

          infos.add(_ZahtevInfo(
            grad: grad,
            vreme: trazeniVreme,
            status: 'obrada',
            pokupljen: false,
            koristiSekundarnu: pending['koristi_sekundarnu'] as bool? ?? false,
          ));
          continue;
        }

        Map<String, dynamic>? selected;
        int selectedRank = -1;
        for (final row in opRows) {
          final status = V3StatusFilters.normalizeStatus(V3StatusFilters.deriveOperativnaStatus(row));
          if (V3StatusFilters.isRejected(status)) continue;
          final rank = _statusPriorityForCell(status) + ((row['pokupljen_at'] != null) ? 10 : 0);
          if (rank > selectedRank) {
            selected = row;
            selectedRank = rank;
          }
        }

        if (selected == null) continue;

        final status = V3StatusFilters.normalizeStatus(V3StatusFilters.deriveOperativnaStatus(selected));
        final opPolazakAt = _normalizeValidTime(selected['polazak_at']?.toString());
        final displayVreme = opPolazakAt ?? '—';

        infos.add(_ZahtevInfo(
          grad: grad,
          vreme: displayVreme,
          status: status,
          pokupljen: selected['pokupljen_at'] != null,
          koristiSekundarnu: selected['koristi_sekundarnu'] as bool? ?? false,
        ));
      }

      final bestByGrad = <String, _ZahtevInfo>{};
      for (final info in infos) {
        final current = bestByGrad[info.grad];
        if (current == null || _statusPriorityForCell(info.status) > _statusPriorityForCell(current.status)) {
          bestByGrad[info.grad] = info;
        }
      }
      newMap[dan] = bestByGrad.values.toList();
    }
    if (mounted) {
      setState(() {
        _rasporedMap
          ..clear()
          ..addAll(newMap);
      });
    }
  }

  bool _isDodelaStatusAktivan(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    const inactiveStatuses = {
      'inactive',
      'neaktivan',
      'otkazan',
      'cancelled',
      'deleted',
    };
    return !inactiveStatuses.contains(normalized);
  }

  Future<void> _reloadTrenutnaDodelaForPutnik(String putnikId) async {
    try {
      final rows = await supabase
          .from('v3_trenutna_dodela')
          .select('termin_id, vozac_auth_id, status')
          .eq('putnik_auth_id', putnikId);

      final next = <String, String>{};
      for (final row in (rows as List<dynamic>)) {
        final mapped = row as Map<String, dynamic>;
        final status = mapped['status']?.toString() ?? '';
        if (!_isDodelaStatusAktivan(status)) continue;

        final terminId = mapped['termin_id']?.toString().trim() ?? '';
        final vozacId = mapped['vozac_auth_id']?.toString().trim() ?? '';
        if (terminId.isEmpty || vozacId.isEmpty) continue;

        next[terminId] = vozacId;
      }

      if (!mounted) return;
      V3StateUtils.safeSetState(this, () {
        _activeVozacByTerminId = next;
      });
    } catch (e) {
      debugPrint('[V3PutnikProfilScreen] _reloadTrenutnaDodelaForPutnik error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // TIME PICKER
  // ─────────────────────────────────────────────────────────────────
  /// Vraća datum za dati dan abbr u tekućoj sedmici.
  Future<void> _updatePolazak(String dan, String grad, String? novoVreme,
      {_ZahtevInfo? trenutniInfo, bool koristiSekundarnu = false}) async {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;
    final validNovoVreme = _normalizeValidTime(novoVreme);
    final datumPolaska = V3DanHelper.datumZaDanAbbrUTekucojSedmici(
      dan,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );

    if (novoVreme != null && validNovoVreme == null) {
      if (mounted) V3AppSnackBar.warning(context, V3PutnikProfilMessages.invalidTermTime);
      return;
    }

    try {
      if (validNovoVreme == null) {
        // Otkaži postojeći zahtev
        if (trenutniInfo == null) return;
        await V3ZahtevService.otkaziPolazakPutnikaPoKontekstu(
          putnikId: putnikId,
          datum: datumPolaska,
          grad: grad,
          otkazaoPutnikId: putnikId,
        );
        if (mounted) V3AppSnackBar.success(context, V3PutnikProfilMessages.tripCanceled(dan, grad));
      } else {
        // Sačuvaj izmenu po kontekstu (putnik + dan + grad)
        final putnikCache = V3MasterRealtimeManager.instance.putniciCache[putnikId];
        final tipPutnika = putnikCache?['tip_putnika'] as String? ?? 'dnevni';
        final brojMesta = tipPutnika == 'posiljka' ? 0 : 1; // posiljka ne zauzima putničko mesto
        await V3ZahtevService.sacuvajPolazakPutnikaPoKontekstu(
          putnikId: putnikId,
          datum: datumPolaska,
          grad: grad,
          novoVreme: validNovoVreme,
          brojMesta: brojMesta,
          koristiSekundarnu: koristiSekundarnu,
          updatedBy: V3AuditKorisnik.normalize(putnikId),
        );
        if (mounted) {
          V3AppSnackBar.success(context, V3PutnikProfilMessages.requestReceived);
        }
      }
    } catch (e) {
      V3ErrorUtils.asyncError(this, context, e);
    }
  }

  Future<void> _showTimePicker(BuildContext ctx, String dan, String grad, _ZahtevInfo? info) async {
    // Scenario 2: zahtev u obradi — blokirati sve akcije
    if (V3StatusFilters.isPending(info?.status)) {
      if (mounted) V3AppSnackBar.info(ctx, V3PutnikProfilMessages.requestPendingDispatcher);
      return;
    }
    // Scenario 6: putnik je već pokupljen — ne može da otkazuje
    if (V3StatusFilters.isActionLocked(status: info?.status, pokupljen: info?.pokupljen ?? false)) {
      if (mounted) V3AppSnackBar.info(ctx, V3PutnikProfilMessages.alreadyPickedUp);
      return;
    }
    // Scenario 5: zaključavanje 15 min pre polaska
    final datumPolaska = V3DanHelper.datumZaDanAbbrUTekucojSedmici(
      dan,
      anchor: V3DanHelper.schedulingWeekAnchor(),
    );
    final datumIso = V3DanHelper.toIsoDate(datumPolaska);
    final neradanRazlog = getNeradanDanRazlog(datumIso: datumIso, grad: grad.toLowerCase());
    if (neradanRazlog != null) {
      if (mounted) {
        V3AppSnackBar.info(ctx, V3PutnikProfilMessages.nonWorkingDay(datumIso, neradanRazlog));
      }
      return;
    }

    final now = DateTime.now();
    final dayFullName = V3DanHelper.fullName(datumPolaska);
    final vremena = getRasporedVremena(grad.toLowerCase(), navBarTypeNotifier.value, day: dayFullName)
        .where((v) => _normalizeValidTime(v) != null)
        .toList();
    final currentVreme = info?.vreme;
    final hasActive =
        info != null && !V3StatusFilters.isCanceledOrRejected(info.status) && !V3StatusFilters.isOfferLike(info.status);
    // Provera da li putnik ima drugu adresu za ovaj grad
    final putnikId = _putnikData['id']?.toString();
    final putnikCache = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    final hasSecondary =
        grad == 'BC' ? (putnikCache?['adresa_bc_id_2'] != null) : (putnikCache?['adresa_vs_id_2'] != null);
    String? secondaryId;
    if (grad == 'BC') {
      secondaryId = putnikCache?['adresa_bc_id_2'] as String?;
    } else {
      secondaryId = putnikCache?['adresa_vs_id_2'] as String?;
    }
    final secondaryNaziv = V3AdresaService.getAdresaById(secondaryId)?.naziv ?? 'Druga adresa';
    bool koristiSekundarnu = info?.koristiSekundarnu ?? false;
    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: V3ContainerUtils.gradientContainer(
            width: 320,
            gradient: V3ThemeManager().currentGradient,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      Text(
                        grad == 'BC' ? '🏙️ BC polazak' : '🌆 VS polazak',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getDanLabel(dan),
                        style: TextStyle(color: V3StyleHelper.whiteAlpha5, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                // Address Selector (Prikazuje se samo ako postoji druga adresa)
                if (hasSecondary)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: InkWell(
                      onTap: () => setDialogState(() => koristiSekundarnu = !koristiSekundarnu),
                      borderRadius: BorderRadius.circular(8),
                      child: V3ContainerUtils.styledContainer(
                        padding: const EdgeInsets.all(10),
                        backgroundColor: V3StyleHelper.whiteAlpha05,
                        border: Border.all(
                          color: Colors.white12,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Icon(
                              koristiSekundarnu ? Icons.location_on : Icons.location_on_outlined,
                              color: Colors.white54,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    koristiSekundarnu ? 'Druga adresa' : 'Primarna adresa',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    koristiSekundarnu
                                        ? secondaryNaziv
                                        : (grad == 'BC'
                                            ? (V3AdresaService.getAdresaById(putnikCache?['adresa_bc_id'] as String?)
                                                    ?.naziv ??
                                                'Glavna adresa')
                                            : (V3AdresaService.getAdresaById(putnikCache?['adresa_vs_id'] as String?)
                                                    ?.naziv ??
                                                'Glavna adresa')),
                                    style: TextStyle(
                                      color: koristiSekundarnu ? Colors.greenAccent : Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: koristiSekundarnu,
                              onChanged: (val) => setDialogState(() => koristiSekundarnu = val),
                              activeColor: Colors.orange,
                              activeTrackColor: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Grid vremena
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Otkaži dugme
                      if (hasActive)
                        SizedBox(
                          width: double.infinity,
                          child: V3ButtonUtils.outlinedButton(
                            onPressed: () async {
                              Navigator.of(dialogCtx).pop();
                              await _updatePolazak(dan, grad, null, trenutniInfo: info);
                            },
                            text: 'Otkaži termin',
                            icon: Icons.cancel_outlined,
                            borderColor: Colors.redAccent,
                            foregroundColor: Colors.redAccent,
                            fontSize: 14,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      if (hasActive) const SizedBox(height: 10),
                      if (hasActive) const Divider(color: Colors.white24, height: 1),
                      if (hasActive) const SizedBox(height: 10),
                      // Wrap grid
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: vremena.map((vreme) {
                          final isSelected =
                              currentVreme != null && V3StringUtils.safeSubstringTime(currentVreme) == vreme;
                          // Scenario 5: zaključaj dugme 15 min pre polaska
                          final parts = vreme.split(':');
                          final polazak = DateTime(
                            datumPolaska.year,
                            datumPolaska.month,
                            datumPolaska.day,
                            int.parse(parts[0]),
                            int.parse(parts[1]),
                          );
                          final isLocked = now.isAfter(polazak.subtract(const Duration(minutes: 15)));
                          return SizedBox(
                            width: 82,
                            child: OutlinedButton(
                              onPressed: isLocked
                                  ? () async {
                                      Navigator.of(dialogCtx).pop();
                                      final unlockAt = V3DanHelper.nextSchedulingUnlock(now: now);
                                      final unlockStr =
                                          '${unlockAt.day}.${unlockAt.month}.${unlockAt.year}. ${unlockAt.hour.toString().padLeft(2, '0')}:${unlockAt.minute.toString().padLeft(2, '0')}';
                                      await Future<void>.delayed(const Duration(milliseconds: 120));
                                      if (!mounted) return;
                                      V3AppSnackBar.info(
                                          ctx, V3PutnikProfilMessages.schedulingLocked(vreme, unlockStr));
                                    }
                                  : () async {
                                      Navigator.of(dialogCtx).pop();
                                      await _updatePolazak(dan, grad, vreme,
                                          trenutniInfo: info, koristiSekundarnu: koristiSekundarnu);
                                    },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: isLocked
                                    ? V3StyleHelper.whiteAlpha05
                                    : isSelected
                                        ? Colors.green.withValues(alpha: 0.45)
                                        : V3StyleHelper.whiteAlpha15,
                                side: BorderSide(
                                  color: isLocked
                                      ? Colors.white12
                                      : isSelected
                                          ? Colors.greenAccent
                                          : Colors.white60,
                                  width: isSelected ? 2.5 : 1.5,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSelected) const Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                                  Text(
                                    vreme,
                                    style: TextStyle(
                                      color: isLocked
                                          ? Colors.white24
                                          : isSelected
                                              ? Colors.white
                                              : Colors.white,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                // Zatvori
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: V3ButtonUtils.textButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    text: 'Zatvori',
                    foregroundColor: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Helper za konverziju kratice dana u puni naziv koristeći V3DanHelper.
  String _getDanLabel(String danAbbr) {
    try {
      final datum = V3DanHelper.datumZaDanAbbrUTekucojSedmici(
        danAbbr,
        anchor: V3DanHelper.schedulingWeekAnchor(),
      );
      return V3DanHelper.fullName(datum);
    } catch (e) {
      // Fallback ako kratica nije validna
      return danAbbr;
    }
  }

  Future<void> _logout() async {
    final ok = await V3DialogHelper.showConfirmDialog(
      context,
      title: 'Odjava',
      message: 'Da li ste sigurni da želite da se odjavite?',
      confirmText: 'Odjavi se',
      cancelText: 'Otkaži',
      isDangerous: true,
    );
    if (ok != true || !mounted) return;
    // Otkaži stream subscription prije brisanja sesije
    V3StreamUtils.cancelSubscription('putnik_profil_cache');
    // Obrisi sesiju i kredencijale
    V3PutnikService.currentPutnik = null;
    await V3BiometricService().clearCredentials();
    await V3FirebaseSmsService.signOut();
    await V3ClosedAuthService.clearFirebasePutnikPhone();
    await V3ClosedAuthService.clearFirebaseVozacPhone();
    if (!mounted) return;
    V3AppSnackBar.success(context, V3PutnikProfilMessages.logoutSuccess);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const V3WelcomeScreen()),
      (r) => false,
    );
  }

  // _showAlternativaDialog obrisan jer alternativa ide samo preko push notifikacije.
  // ─── STATUS WIDGET ───────────────────────────────────────────────
  Widget _buildVozacEtaWidgets() {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return const SizedBox.shrink();
    final rm = V3MasterRealtimeManager.instance;
    final operativniTermini = rm.operativnaAssignedCache.values
        .where((r) => (r['created_by']?.toString() ?? '') == putnikId)
        .where((r) => !V3StatusFilters.isCanceledOrRejected(V3StatusFilters.deriveOperativnaStatus(r)))
        .where((r) => ((r['gps_status']?.toString() ?? '').trim().toLowerCase()) == 'tracking')
        .where((r) => V3StatusFilters.isApproved(V3StatusFilters.deriveOperativnaStatus(r)))
        .toList();

    final now = DateTime.now();
    final kandidati = <Map<String, dynamic>>[];

    for (final row in operativniTermini) {
      final terminId = row['id']?.toString().trim() ?? '';
      if (terminId.isEmpty) continue;
      final vozacId = _activeVozacByTerminId[terminId];
      if (vozacId == null || vozacId.isEmpty) continue;

      final vreme = V3StringUtils.safeSubstringTime((row['polazak_at'] as String?) ?? '');
      if (vreme.isEmpty) continue;

      final datum = DateTime.tryParse(row['datum'] as String? ?? '');
      if (datum == null) continue;

      final parts = vreme.split(':');
      if (parts.length < 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;

      final polazak = DateTime(datum.year, datum.month, datum.day, hour, minute);
      final krajPrikaza = polazak.add(const Duration(hours: 1));

      if (now.isAfter(krajPrikaza)) continue;

      kandidati.add({
        'row': row,
        'terminId': terminId,
        'vozacId': vozacId,
        'vreme': vreme,
        'datum': datum,
        'polazak': polazak,
      });
    }

    if (kandidati.isEmpty) return const SizedBox.shrink();

    kandidati.sort((a, b) {
      final pa = a['polazak'] as DateTime;
      final pb = b['polazak'] as DateTime;
      final aPast = pa.isBefore(now);
      final bPast = pb.isBefore(now);
      if (aPast != bPast) return aPast ? 1 : -1;
      final da = pa.difference(now).abs().inMinutes;
      final db = pb.difference(now).abs().inMinutes;
      return da.compareTo(db);
    });

    final selected = kandidati.first;

    final row = selected['row'] as Map<String, dynamic>;
    final grad = (row['grad'] as String? ?? '').toUpperCase();
    final vozacId = selected['vozacId'] as String;
    final koristiSekundarnu = row['koristi_sekundarnu'] as bool? ?? false;
    final adresaOverride = row['adresa_override_id'] as String?;
    final mojRouteOrder = (row['route_order'] as num?)?.toInt();

    // Resolvi adresu ovog putnika
    String? mojAdresaId;
    if (adresaOverride != null && adresaOverride.isNotEmpty) {
      mojAdresaId = adresaOverride;
    } else if (grad == 'BC') {
      final adresaBc1 = _putnikData['adresa_bc_id'] as String?;
      final adresaBc2 = _putnikData['adresa_bc_id_2'] as String?;
      mojAdresaId = koristiSekundarnu ? (adresaBc2 ?? adresaBc1) : (adresaBc1 ?? adresaBc2);
    } else if (grad == 'VS') {
      final adresaVs1 = _putnikData['adresa_vs_id'] as String?;
      final adresaVs2 = _putnikData['adresa_vs_id_2'] as String?;
      mojAdresaId = koristiSekundarnu ? (adresaVs2 ?? adresaVs1) : (adresaVs1 ?? adresaVs2);
    }

    final mojaAdresa = V3AdresaService.getAdresaById(mojAdresaId);
    if (mojaAdresa == null || !mojaAdresa.hasValidCoordinates) return const SizedBox.shrink();

    // Pronađi putnike koji su pre ovog na ruti (manji route_order) i resolvi njihove adrese
    final putnikWaypoints = <({double lat, double lng})>[];

    if (mojRouteOrder != null && mojRouteOrder > 1) {
      final prethodnici = rm.operativnaAssignedCache.values.where((r) {
        final rowTerminId = r['id']?.toString().trim() ?? '';
        if (rowTerminId.isEmpty) return false;
        final rowVozacId = _activeVozacByTerminId[rowTerminId];
        if (rowVozacId != vozacId) return false;
        if (r['datum']?.toString() != row['datum']?.toString()) return false;
        if ((r['grad'] as String? ?? '').toUpperCase() != grad) return false;
        final order = (r['route_order'] as num?)?.toInt();
        return order != null && order < mojRouteOrder;
      }).toList()
        ..sort((a, b) {
          final oa = (a['route_order'] as num).toInt();
          final ob = (b['route_order'] as num).toInt();
          return oa.compareTo(ob);
        });

      for (final r in prethodnici) {
        final pPutnikId = r['created_by']?.toString();
        final pOverride = r['adresa_override_id'] as String?;
        final pGrad = (r['grad'] as String? ?? '').toUpperCase();
        final pKoristiSek = r['koristi_sekundarnu'] as bool? ?? false;

        String? pAdresaId;
        if (pOverride != null && pOverride.isNotEmpty) {
          pAdresaId = pOverride;
        } else if (pPutnikId != null) {
          final pData = rm.putniciCache[pPutnikId];
          if (pData != null) {
            if (pGrad == 'BC') {
              final a1 = pData['adresa_bc_id'] as String?;
              final a2 = pData['adresa_bc_id_2'] as String?;
              pAdresaId = pKoristiSek ? (a2 ?? a1) : (a1 ?? a2);
            } else if (pGrad == 'VS') {
              final a1 = pData['adresa_vs_id'] as String?;
              final a2 = pData['adresa_vs_id_2'] as String?;
              pAdresaId = pKoristiSek ? (a2 ?? a1) : (a1 ?? a2);
            }
          }
        }

        final pAdresa = V3AdresaService.getAdresaById(pAdresaId);
        if (pAdresa != null && pAdresa.hasValidCoordinates) {
          putnikWaypoints.add((lat: pAdresa.gpsLat!, lng: pAdresa.gpsLng!));
        }
      }
    }

    // Dodaj adresu ovog putnika kao poslednju tačku
    putnikWaypoints.add((lat: mojaAdresa.gpsLat!, lng: mojaAdresa.gpsLng!));

    return V3VozacStatusWidget(
      vozacId: vozacId,
      putnikWaypoints: putnikWaypoints,
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final putnikId = _putnikData['id']?.toString();
    final tip = _putnikData['tip_putnika'] as String? ?? 'radnik';
    final cenaPoDanu = (_putnikData['cena_po_danu'] as num?)?.toDouble() ?? 0.0;
    final cenaPoPokupljenju = (_putnikData['cena_po_pokupljenju'] as num?)?.toDouble() ?? 0.0;
    final koristiCenuPoPokupljenju = tip == 'dnevni' || tip == 'posiljka';
    final efektivnaCena = koristiCenuPoPokupljenju ? cenaPoPokupljenju : cenaPoDanu;
    final cenaInfo = efektivnaCena > 0
        ? '${koristiCenuPoPokupljenju ? 'Cena po pokupljenju' : 'Cena po danu'}: ${efektivnaCena.toStringAsFixed(0)} RSD'
        : null;
    final imePrezime = _putnikData['ime_prezime'] as String? ?? '';
    final telefon = _putnikData['telefon_1'] as String? ?? '';
    final telefon2 = _putnikData['telefon_2'] as String? ?? '';
    final adresaBcId = _putnikData['adresa_bc_id'] as String?;
    final adresaVsId = _putnikData['adresa_vs_id'] as String?;
    final adresaBcId2 = _putnikData['adresa_bc_id_2'] as String?;
    final adresaVsId2 = _putnikData['adresa_vs_id_2'] as String?;
    final adresaBcNaziv = V3AdresaService.getNazivAdreseById(adresaBcId);
    final adresaVsNaziv = V3AdresaService.getNazivAdreseById(adresaVsId);
    final adresaBcNaziv2 = V3AdresaService.getNazivAdreseById(adresaBcId2);
    final adresaVsNaziv2 = V3AdresaService.getNazivAdreseById(adresaVsId2);
    final stats = V3PutnikStatistikaService.getTekuciMesec(putnikId ?? '');
    final ukupanDug = V3PutnikStatistikaService.getUkupanDugZaSveMesece(putnikId ?? '');
    final nedeljaOpseg = _formatNedeljaOpsegLabel();
    final nedeljaInfo = 'Aktivna nedelja: $nedeljaOpseg';
    return ValueListenableBuilder<ThemeData>(
      valueListenable: V3ThemeManager().themeNotifier,
      builder: (context, _, __) => V3ContainerUtils.backgroundContainer(
        gradient: V3ThemeManager().currentGradient,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Forced update gate
                      const V3UpdateBanner(),
                      // ── NOTIFIKACIJE UPOZORENJE ──────────────────────────
                      if (_notifStatus.isDenied || _notifStatus.isPermanentlyDenied)
                        _NotifBanner(onEnable: _requestNotifPermission),
                      const SizedBox(height: 8),
                      // ── HEADER CARD ──────────────────────────────────────
                      _buildHeaderCard(
                        tip: tip,
                        imePrezime: imePrezime,
                        telefon: telefon,
                        telefon2: telefon2,
                        adresaBcNaziv: adresaBcNaziv,
                        adresaVsNaziv: adresaVsNaziv,
                        adresaBcNaziv2: adresaBcNaziv2,
                        adresaVsNaziv2: adresaVsNaziv2,
                      ),
                      const SizedBox(height: 16),
                      // ── STATUS WIDGET ────────────────────────────────────
                      _buildVozacEtaWidgets(),
                      const SizedBox(height: 10),
                      _buildStatistikaCard(tip: tip, stats: stats, cenaInfo: cenaInfo, ukupanDug: ukupanDug),
                      const SizedBox(height: 10),
                      _buildDetaljneStatistikeSection(
                        putnikId: putnikId,
                        imePrezime: imePrezime,
                        tipPutnika: tip,
                      ),
                      const SizedBox(height: 16),
                      // ── RASPORED TERMINA ─────────────────────────────────
                      _buildRasporedCard(nedeljaInfo: nedeljaInfo),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: const V3NeradniDaniBanner(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────────────────────────
  Widget _buildHeaderCard({
    required String tip,
    required String imePrezime,
    required String telefon,
    String telefon2 = '',
    required String? adresaBcNaziv,
    required String? adresaVsNaziv,
    String? adresaBcNaziv2,
    String? adresaVsNaziv2,
  }) {
    final avatarColors = _avatarColors(tip);
    final tipLabel = _tipLabel(tip);
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(20),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _WeatherMiniCell(snapshot: _weatherByGrad['BC']),
                ),
              ),
              V3LiveClockText(
                style: TextStyle(
                  color: V3StyleHelper.whiteAlpha75,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _WeatherMiniCell(snapshot: _weatherByGrad['VS']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              IconButton(
                icon: const Text('🎨', style: TextStyle(fontSize: 18)),
                tooltip: 'Tema',
                onPressed: () async {
                  await V3ThemeManager().nextTheme();
                  V3StateUtils.safeSetState(this, () {});
                  if (!mounted) return;
                  V3AppSnackBar.info(context, V3PutnikProfilMessages.themeChanged);
                },
              ),
              Expanded(
                child: Text(
                  imePrezime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.red),
                tooltip: 'Odjava',
                onPressed: _logout,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Tip badge
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (tip.toLowerCase() != 'radnik') _Badge(label: tipLabel, color: avatarColors[0]),
            ],
          ),
          if (telefon.isNotEmpty || telefon2.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.phone, color: Colors.white54, size: 13),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    [if (telefon.isNotEmpty) telefon, if (telefon2.isNotEmpty) telefon2].join('  •  '),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: V3StyleHelper.whiteAlpha9,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          // Adrese
          if (adresaBcNaziv != null || adresaVsNaziv != null) ...[
            const SizedBox(height: 12),
            Divider(color: V3StyleHelper.whiteAlpha15),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // BC kolona
                if (adresaBcNaziv != null && adresaBcNaziv.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.location_city, color: Colors.white38, size: 12),
                          const SizedBox(width: 4),
                          Text('Bela Crkva',
                              style: TextStyle(
                                  color: V3StyleHelper.whiteAlpha45, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.home, color: Colors.white60, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(adresaBcNaziv,
                                  style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                        if (adresaBcNaziv2 != null && adresaBcNaziv2.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.home_outlined, color: Colors.white60, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(adresaBcNaziv2,
                                    style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                    overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                      ],
                    ),
                  ),
                if (adresaBcNaziv != null && adresaVsNaziv != null)
                  Container(
                      width: 1,
                      height: V3ContainerUtils.responsiveHeight(context, 40),
                      color: Colors.white12,
                      margin: const EdgeInsets.symmetric(horizontal: 10)),
                // VS kolona
                if (adresaVsNaziv != null && adresaVsNaziv.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.location_city, color: Colors.white38, size: 12),
                          const SizedBox(width: 4),
                          Text('Vrsac',
                              style: TextStyle(
                                  color: V3StyleHelper.whiteAlpha45, fontSize: 14, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.work, color: Colors.white60, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(adresaVsNaziv,
                                  style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                        if (adresaVsNaziv2 != null && adresaVsNaziv2.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.work_outline, color: Colors.white60, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(adresaVsNaziv2,
                                    style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 14),
                                    overflow: TextOverflow.ellipsis)),
                          ]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatistikaCard({
    required String tip,
    required V3PutnikMesecnaStatistika stats,
    String? cenaInfo,
    required double ukupanDug,
  }) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(16),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              stats.mesecNaziv,
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Stanje vožnji i naplate',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          if (cenaInfo != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                cenaInfo,
                textAlign: TextAlign.center,
                style: TextStyle(color: V3StyleHelper.whiteAlpha9, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _modelNaplataLabel(tip),
            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _kpiTile('Pokupljen', '${stats.pokupljeno}', Colors.lightBlueAccent),
              _kpiTile('Vožnji', '${stats.ukupnoVoznji}', Colors.greenAccent),
              _kpiTile('Otkazano', '${stats.otkazano}', Colors.redAccent),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: V3StyleHelper.whiteAlpha15),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Plaćeno', style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${stats.naplacenoIznos.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dug', style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${stats.dugIznos.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ukupan dug', style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${ukupanDug.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiTile(String label, String value, Color color) {
    return V3ContainerUtils.styledContainer(
      width: 76,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _modelNaplataLabel(String tip) {
    final normalized = tip.toLowerCase();
    if (normalized == 'radnik' || normalized == 'ucenik') {
      return 'Model: cena po danu (jedna cena za jedno ili više pokupljenja u danu).';
    }
    return 'Model: cena po pokupljenju (svako pokupljenje se naplaćuje).';
  }

  Widget _buildDetaljneStatistikeSection({
    required String? putnikId,
    required String imePrezime,
    required String tipPutnika,
  }) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(12),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Detaljne statistike',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Pregled po mesecima',
            textAlign: TextAlign.center,
            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12),
          ),
          const SizedBox(height: 10),
          V3ButtonUtils.outlinedButton(
            onPressed: (putnikId == null || putnikId.isEmpty)
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => V3PutnikStatistikaScreen(
                          putnikId: putnikId,
                          imePrezime: imePrezime,
                          tipPutnika: tipPutnika,
                        ),
                      ),
                    );
                  },
            text: 'Otvori detaljne statistike',
            icon: Icons.analytics_outlined,
            borderColor: Colors.white30,
            foregroundColor: Colors.white,
            borderRadius: BorderRadius.circular(10),
            fontSize: 13,
          ),
        ],
      ),
    );
  }

  Widget _buildRasporedCard({required String nedeljaInfo}) {
    final dani = V3DanHelper.workdayAbbrs.toList(); // pon-pet (radni dani)
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.all(16),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              nedeljaInfo,
              style: TextStyle(
                color: V3StyleHelper.whiteAlpha75,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              '🕐 Raspored termina',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Header
          Row(
            children: [
              const SizedBox(width: 96),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'BC',
                        style: TextStyle(
                          color: V3StyleHelper.whiteAlpha65,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '(Bela Crkva)',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VS',
                        style: TextStyle(
                          color: V3StyleHelper.whiteAlpha65,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '(Vrsac)',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: V3StyleHelper.whiteAlpha1),
          ...dani.map((dan) {
            final infos = _rasporedMap[dan] ?? [];
            final bcInfo = infos.where((i) => i.grad == 'BC').firstOrNull;
            final vsInfo = infos.where((i) => i.grad == 'VS').firstOrNull;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      _getDanLabel(dan),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _ZahtevCell(
                        info: bcInfo,
                        onTap: () => _showTimePicker(context, dan, 'BC', bcInfo),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: _ZahtevCell(
                        info: vsInfo,
                        onTap: () => _showTimePicker(context, dan, 'VS', vsInfo),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────
  List<Color> _avatarColors(String tip) {
    switch (tip.toLowerCase()) {
      case 'ucenik':
        return [Colors.blue.shade400, Colors.indigo.shade600];
      case 'posiljka':
        return [Colors.purple.shade400, Colors.deepPurple.shade600];
      case 'dnevni':
        return [Colors.green.shade400, Colors.teal.shade600];
      default:
        return [Colors.orange.shade400, Colors.deepOrange.shade600];
    }
  }

  String _tipLabel(String tip) {
    switch (tip.toLowerCase()) {
      case 'ucenik':
        return '🎓 Učenik';
      case 'posiljka':
        return '📦 Pošiljka';
      case 'dnevni':
        return '📅 Dnevni';
      case 'radnik':
        return '💼 Radnik';
      default:
        return '👤 Putnik';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────
// Helper data class
// ─────────────────────────────────────────────────────────────────────
class _ZahtevInfo {
  final String grad;
  final String vreme;
  final String status;
  final bool pokupljen;
  final bool koristiSekundarnu;
  const _ZahtevInfo({
    required this.grad,
    required this.vreme,
    required this.status,
    this.pokupljen = false,
    this.koristiSekundarnu = false,
  });
}

// ─────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────
class _NotifBanner extends StatelessWidget {
  final VoidCallback onEnable;
  const _NotifBanner({required this.onEnable});
  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      backgroundColor: Colors.red.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.redAccent),
      child: Row(
        children: [
          const Icon(Icons.notifications_off, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifikacije isključene!',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Nećete videti potvrde vožnji.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          V3ButtonUtils.textButton(
            onPressed: onEnable,
            text: 'UKLJUČI',
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      backgroundColor: color.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: V3StyleHelper.whiteAlpha25),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _WeatherMiniCell extends StatelessWidget {
  final V3WeatherSnapshot? snapshot;

  const _WeatherMiniCell({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final data = snapshot;
    if (data == null) {
      return Text(
        '—',
        style: TextStyle(
          color: V3StyleHelper.whiteAlpha5,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final temp = '${data.temperatureC.round()}°';
    final rain = data.precipitationProbability != null ? ' · ${data.precipitationProbability}%' : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.icon,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '$temp$rain',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ZahtevCell extends StatelessWidget {
  final _ZahtevInfo? info;
  final VoidCallback? onTap;
  const _ZahtevCell({this.info, this.onTap});
  @override
  Widget build(BuildContext context) {
    if (info == null) {
      return GestureDetector(
        onTap: onTap,
        child: V3ContainerUtils.styledContainer(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          backgroundColor: V3StyleHelper.whiteAlpha25,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: V3StyleHelper.whiteAlpha5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 12, color: Colors.black),
              const SizedBox(width: 3),
              Text(
                'dodaj',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final badgeStyle = V3StatusPresentation.forCell(
      status: info!.status,
      pokupljen: info!.pokupljen,
    );
    final statusColor = badgeStyle.color;
    final statusIcon = badgeStyle.icon;
    final vreme = V3StringUtils.safeSubstringTime(info!.vreme);
    return GestureDetector(
      onTap: onTap,
      child: V3ContainerUtils.styledContainer(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        backgroundColor: statusColor.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.90),
          width: 1.2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$statusIcon $vreme',
                style: TextStyle(
                  color: V3StyleHelper.whiteAlpha9,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 10, color: V3StyleHelper.whiteAlpha3),
          ],
        ),
      ),
    );
  }
}
// _AltOptionBtn obrisan jer se više ne koristi u ovom fajlu.
