import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v2_theme_manager.dart';
import '../services/v3/v3_adresa_service.dart';
import '../services/v3/v3_dug_service.dart';
import '../services/v3/v3_zahtev_service.dart';
import '../utils/v3_app_snack_bar.dart';

class V3PutnikProfilScreen extends StatefulWidget {
  final Map<String, dynamic> putnikData;

  const V3PutnikProfilScreen({super.key, required this.putnikData});

  @override
  State<V3PutnikProfilScreen> createState() => _V3PutnikProfilScreenState();
}

class _V3PutnikProfilScreenState extends State<V3PutnikProfilScreen> with WidgetsBindingObserver {
  late Map<String, dynamic> _putnikData;
  PermissionStatus _notifStatus = PermissionStatus.granted;

  // Zahtevi po danu
  // key = dan kratica npr 'pon', value = lista zahteva (BC i VS)
  final Map<String, List<_ZahtevInfo>> _rasporedMap = {};

  // Dugovanje
  double _ukupnoDugovanje = 0.0;
  int _brojNeplacenih = 0;

  late StreamSubscription<void> _cacheSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _putnikData = Map<String, dynamic>.from(widget.putnikData);
    _checkNotifPermission();
    _refresh();

    // Pratimo promjene cache-a
    _cacheSub = V3MasterRealtimeManager.instance.v3StreamFromCache<void>(
      tables: const ['v3_putnici', 'v3_zahtevi', 'v3_operativna_nedelja'],
      build: () {},
    ).listen((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cacheSub.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotifPermission();
    }
  }

  Future<void> _checkNotifPermission() async {
    final status = await Permission.notification.status;
    if (mounted) setState(() => _notifStatus = status);
  }

  Future<void> _requestNotifPermission() async {
    final status = await Permission.notification.request();
    if (mounted) setState(() => _notifStatus = status);
    if (status.isPermanentlyDenied) await openAppSettings();
  }

  void _refresh() {
    final putnikId = _putnikData['id']?.toString();
    if (putnikId == null) return;

    // Osvježi putnik iz cache-a
    final cached = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    if (cached != null) _putnikData = Map<String, dynamic>.from(cached);

    // Raspored po danima iz v3_zahtevi — filtrira po tacnom datumu
    const dani = ['pon', 'uto', 'sre', 'cet', 'pet'];
    final newMap = <String, List<_ZahtevInfo>>{};
    for (final dan in dani) {
      final datumIso = V3DanHelper.datumZaDanAbbr(dan).toIso8601String().split('T')[0];
      final bcList =
          V3ZahtevService.getZahteviByDatumAndGrad(datumIso, 'BC').where((z) => z.putnikId == putnikId).toList();
      final vsList =
          V3ZahtevService.getZahteviByDatumAndGrad(datumIso, 'VS').where((z) => z.putnikId == putnikId).toList();

      final infos = <_ZahtevInfo>[];
      for (final z in bcList) {
        final displayVreme = z.status == 'odobreno' && z.dodeljenoVreme != null ? z.dodeljenoVreme! : z.zeljenoVreme;
        infos.add(
            _ZahtevInfo(grad: 'BC', vreme: displayVreme, status: z.status, zahtevId: z.id, pokupljen: z.pokupljen));
      }
      for (final z in vsList) {
        final displayVreme = z.status == 'odobreno' && z.dodeljenoVreme != null ? z.dodeljenoVreme! : z.zeljenoVreme;
        infos.add(
            _ZahtevInfo(grad: 'VS', vreme: displayVreme, status: z.status, zahtevId: z.id, pokupljen: z.pokupljen));
      }
      newMap[dan] = infos;
    }

    // Dugovanje iz v3_dnevne_operacije
    double ukupno = 0.0;
    int brNeplacenih = 0;
    for (final dug in V3DugService.getDugovi()) {
      if (dug.putnikId == putnikId) {
        ukupno += dug.iznos;
        brNeplacenih++;
      }
    }

    if (mounted) {
      setState(() {
        _rasporedMap
          ..clear()
          ..addAll(newMap);
        _ukupnoDugovanje = ukupno;
        _brojNeplacenih = brNeplacenih;
      });
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

    try {
      if (novoVreme == null) {
        // Otkaži postojeći zahtev
        if (trenutniInfo == null) return;
        await V3ZahtevService.otkaziZahtev(trenutniInfo.zahtevId, otkazaoPutnikId: putnikId);
        if (mounted) V3AppSnackBar.success(context, '✅ Polazak otkazan: $dan $grad');
      } else if (trenutniInfo != null && (trenutniInfo.status == 'obrada' || trenutniInfo.status == 'odobreno')) {
        // Ažuriraj vreme na postojećem zahtevu (vraća u obrada)
        // Napomena: ovde bismo mogli dodati i promenu adrese ako je potrebno, ali za sada samo vreme
        await V3ZahtevService.updateZeljenoVreme(trenutniInfo.zahtevId, novoVreme);
        if (mounted) V3AppSnackBar.success(context, '✅ Zahtev ažuriran: $novoVreme');
      } else {
        // Kreiraj novi zahtev
        final putnikCache = V3MasterRealtimeManager.instance.putniciCache[putnikId];
        final imePrezime = putnikCache?['ime_prezime'] as String? ?? '';
        final brojMesta = (putnikCache?['broj_mesta'] as int?) ?? 1;
        final zahtev = V3Zahtev(
          id: const Uuid().v4(),
          putnikId: putnikId,
          imePrezime: imePrezime,
          datum: V3DanHelper.datumZaDanAbbr(dan),
          grad: grad,
          zeljenoVreme: novoVreme,
          brojMesta: brojMesta,
          status: 'obrada',
          koristiSekundarnu: koristiSekundarnu,
          aktivno: true,
          izvorId: putnikId,
        );
        await V3ZahtevService.createZahtev(zahtev, createdBy: 'putnik:$imePrezime');
        if (mounted) {
          V3AppSnackBar.success(context,
              '✅ Vaš zahtev je uspešno primljen i biće obrađen u najkraćem roku. Bićete obavešteni o statusu putem aplikacije.');
        }
      }
    } catch (e) {
      if (mounted) V3AppSnackBar.error(context, '❌ Greška: $e');
    }
  }

  Future<void> _showTimePicker(BuildContext ctx, String dan, String grad, _ZahtevInfo? info) async {
    // Scenario 2: zahtev u obradi — blokirati sve akcije
    if (info?.status == 'obrada') {
      if (mounted) V3AppSnackBar.info(ctx, 'Vaš zahtev je u obradi kod dispečera.');
      return;
    }

    // Scenario 5: zaključavanje 15 min pre polaska
    final datumPolaska = V3DanHelper.datumZaDanAbbr(dan);
    final now = DateTime.now();

    final vremena = V2RouteConfig.getVremenaByNavType(grad, navBarTypeNotifier.value);
    final currentVreme = info?.vreme;
    final hasActive = info != null &&
        info.status != 'otkazano' &&
        info.status != 'odbijeno' &&
        info.status != 'alternativa' &&
        info.status != 'ponuda';

    // Provera da li putnik ima drugu adresu za ovaj grad
    final putnikId = _putnikData['id']?.toString();
    final putnikCache = V3MasterRealtimeManager.instance.putniciCache[putnikId];
    final hasSecondary =
        grad == 'BC' ? (putnikCache?['adresa_bc_id_2'] != null) : (putnikCache?['adresa_vs_id_2'] != null);
    final secondaryNaziv = grad == 'BC'
        ? (putnikCache?['adresa_bc_naziv_2'] as String? ?? 'Druga adresa')
        : (putnikCache?['adresa_vs_naziv_2'] as String? ?? 'Druga adresa');

    bool koristiSekundarnu = false;

    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 320,
            decoration: BoxDecoration(
              gradient: V2ThemeManager().currentGradient,
              borderRadius: BorderRadius.circular(16),
            ),
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
                        _daniLabel[dan] ?? dan,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),

                // Address Selector (Prikazuje se samo ako postoji druga adresa)
                if (hasSecondary && !hasActive)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: InkWell(
                      onTap: () => setDialogState(() => koristiSekundarnu = !koristiSekundarnu),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: koristiSekundarnu
                              ? Colors.orange.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          border: Border.all(
                            color: koristiSekundarnu ? Colors.orange : Colors.white12,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              koristiSekundarnu ? Icons.location_on : Icons.location_on_outlined,
                              color: koristiSekundarnu ? Colors.orange : Colors.white54,
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
                                      color: koristiSekundarnu ? Colors.orange : Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    koristiSekundarnu
                                        ? secondaryNaziv
                                        : (grad == 'BC'
                                            ? (putnikCache?['adresa_bc_naziv'] as String? ?? 'Glavna adresa')
                                            : (putnikCache?['adresa_vs_naziv'] as String? ?? 'Glavna adresa')),
                                    style:
                                        const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
                            label: const Text('Otkaži termin', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () async {
                              Navigator.of(dialogCtx).pop();
                              await _updatePolazak(dan, grad, null, trenutniInfo: info);
                            },
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
                              currentVreme != null && currentVreme.length >= 5 && currentVreme.substring(0, 5) == vreme;
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
                                  ? null
                                  : () async {
                                      Navigator.of(dialogCtx).pop();

                                      // Scenario: "Ignore alternative and retry"
                                      // Ako putnik klikne na bilo koje vreme dok je u statusu "alternativa",
                                      // resetujemo zahtev na "obrada" i brišemo ponuđene alternative.
                                      if (info?.status == 'alternativa' || info?.status == 'ponuda') {
                                        await V3ZahtevService.updateStatus(info!.zahtevId, 'obrada',
                                            updatedBy: 'putnik:reset_alternative');
                                        // Ovde možemo stati ili nastaviti sa novim vremenom.
                                        // Budući da je isLocked već proveren, dozvoljavamo promenu vremena.
                                      }

                                      await _updatePolazak(dan, grad, vreme,
                                          trenutniInfo: info, koristiSekundarnu: koristiSekundarnu);
                                    },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: isLocked
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : isSelected
                                        ? Colors.green.withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.1),
                                side: BorderSide(
                                  color: isLocked
                                      ? Colors.white12
                                      : isSelected
                                          ? Colors.green
                                          : Colors.white38,
                                  width: isSelected ? 2 : 1,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSelected) const Icon(Icons.check_circle, color: Colors.green, size: 14),
                                  Text(
                                    vreme,
                                    style: TextStyle(
                                      color: isLocked
                                          ? Colors.white24
                                          : isSelected
                                              ? Colors.white
                                              : Colors.white70,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Zatvori', style: TextStyle(color: Colors.white54)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _daniLabel = {
    'pon': 'Ponedeljak',
    'uto': 'Utorak',
    'sre': 'Sreda',
    'cet': 'Četvrtak',
    'pet': 'Petak',
  };

  Future<void> _logout() async {
    // ...existing code...
  }

  // _showAlternativaDialog obrisan jer alternativa ide samo preko push notifikacije.

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tip = _putnikData['tip_putnika'] as String? ?? 'radnik';
    final imePrezime = _putnikData['ime_prezime'] as String? ?? '';
    final telefon = _putnikData['telefon_1'] as String? ?? '';
    final adresaBcId = _putnikData['adresa_bc_id'] as String?;
    final adresaVsId = _putnikData['adresa_vs_id'] as String?;
    final adresaBcNaziv = V3AdresaService.getNazivAdreseById(adresaBcId);
    final adresaVsNaziv = V3AdresaService.getNazivAdreseById(adresaVsId);
    final cenaPoDanu = (_putnikData['cena_po_danu'] as num?)?.toDouble() ?? 0.0;

    // Avatar inicijali
    final parts = imePrezime.trim().split(' ');
    final initials = '${parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0].toUpperCase() : ''}'
        '${parts.length > 1 && parts.last.isNotEmpty ? parts.last[0].toUpperCase() : ''}';

    return Container(
      decoration: BoxDecoration(gradient: V2ThemeManager().currentGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Moj profil',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.palette, color: Colors.white),
              tooltip: 'Tema',
              onPressed: () async {
                await V2ThemeManager().nextTheme();
                if (mounted) setState(() {});
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              tooltip: 'Odjava',
              onPressed: _logout,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── NOTIFIKACIJE UPOZORENJE ──────────────────────────
              if (_notifStatus.isDenied || _notifStatus.isPermanentlyDenied)
                _NotifBanner(onEnable: _requestNotifPermission),

              const SizedBox(height: 8),

              // ── HEADER CARD ──────────────────────────────────────
              _buildHeaderCard(
                tip: tip,
                imePrezime: imePrezime,
                initials: initials,
                telefon: telefon,
                adresaBcNaziv: adresaBcNaziv,
                adresaVsNaziv: adresaVsNaziv,
              ),

              const SizedBox(height: 16),

              // ── DUGOVANJE ────────────────────────────────────────
              if (cenaPoDanu > 0 || _ukupnoDugovanje > 0) _buildDugovanjeCard(cenaPoDanu: cenaPoDanu),

              if (cenaPoDanu > 0 || _ukupnoDugovanje > 0) const SizedBox(height: 16),

              // ── RASPORED ZAHTEVA ─────────────────────────────────
              _buildRasporedCard(),

              const SizedBox(height: 16),
            ],
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
    required String initials,
    required String telefon,
    required String? adresaBcNaziv,
    required String? adresaVsNaziv,
  }) {
    final avatarColors = _avatarColors(tip);
    final tipLabel = _tipLabel(tip);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: avatarColors,
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: avatarColors[0].withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black38)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Ime
          Text(
            imePrezime,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Tip badge + Telefon badge
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _Badge(label: tipLabel, color: avatarColors[0]),
              if (telefon.isNotEmpty) _Badge(label: '📞 $telefon', color: Colors.white24),
            ],
          ),

          // Adrese
          if (adresaBcNaziv != null || adresaVsNaziv != null) ...[
            const SizedBox(height: 12),
            Divider(color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (adresaBcNaziv != null && adresaBcNaziv.isNotEmpty) ...[
                  const Icon(Icons.home, color: Colors.white60, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    adresaBcNaziv,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                  ),
                ],
                if (adresaBcNaziv != null && adresaVsNaziv != null) const SizedBox(width: 16),
                if (adresaVsNaziv != null && adresaVsNaziv.isNotEmpty) ...[
                  const Icon(Icons.work, color: Colors.white60, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    adresaVsNaziv,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDugovanjeCard({required double cenaPoDanu}) {
    final isCisto = _ukupnoDugovanje <= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCisto
              ? [Colors.green.withValues(alpha: 0.18), Colors.green.withValues(alpha: 0.05)]
              : [Colors.red.withValues(alpha: 0.22), Colors.red.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCisto ? Colors.green.withValues(alpha: 0.35) : Colors.red.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Text(
            'TRENUTNO STANJE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isCisto ? '✅ IZMIRENO' : '${_ukupnoDugovanje.toStringAsFixed(0)} RSD',
            style: TextStyle(
              color: isCisto ? Colors.green.shade200 : Colors.red.shade200,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!isCisto) ...[
            const SizedBox(height: 4),
            Text(
              '$_brojNeplacenih neplaćenih prevoza',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
            ),
          ],
          if (cenaPoDanu > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Cena: ${cenaPoDanu.toStringAsFixed(0)} RSD / dan',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRasporedCard() {
    const dani = ['pon', 'uto', 'sre', 'cet', 'pet'];
    const daniLabel = {
      'pon': 'Ponedeljak',
      'uto': 'Utorak',
      'sre': 'Sreda',
      'cet': 'Četvrtak',
      'pet': 'Petak',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              '🕐 Raspored prevoza',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Aktivni tjedni zahtevi',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              const SizedBox(width: 96),
              Expanded(
                child: Center(
                  child: Text(
                    'BC',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'VS',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withValues(alpha: 0.1)),

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
                      daniLabel[dan] ?? dan,
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
  final String zahtevId;
  final bool pokupljen;

  const _ZahtevInfo({
    required this.grad,
    required this.vreme,
    required this.status,
    required this.zahtevId,
    this.pokupljen = false,
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
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent),
      ),
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
          TextButton(
            onPressed: onEnable,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('UKLJUČI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
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

class _ZahtevCell extends StatelessWidget {
  final _ZahtevInfo? info;
  final VoidCallback? onTap;
  const _ZahtevCell({this.info, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (info == null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 12, color: Colors.black),
              const SizedBox(width: 3),
              Text('dodaj', style: TextStyle(color: Colors.black, fontSize: 11)),
            ],
          ),
        ),
      );
    }

    final Color statusColor;
    final String statusIcon;
    if (info!.pokupljen) {
      statusColor = Colors.blue;
      statusIcon = '🚗';
    } else {
      switch (info!.status) {
        case 'odobreno':
          statusColor = Colors.green;
          statusIcon = '✅';
        case 'obrada':
          statusColor = Colors.orange;
          statusIcon = '⏳';
        case 'alternativa':
        case 'ponuda':
          statusColor = Colors.orangeAccent;
          statusIcon = '🔄';
        case 'odbijeno':
        case 'otkazano':
          statusColor = Colors.red;
          statusIcon = '🚫';
        default:
          statusColor = Colors.grey;
          statusIcon = '•';
      }
    }

    final vreme = info!.vreme.length >= 5 ? info!.vreme.substring(0, 5) : info!.vreme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$statusIcon $vreme',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 10, color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}

// _AltOptionBtn obrisan jer se više ne koristi u ovom fajlu.
