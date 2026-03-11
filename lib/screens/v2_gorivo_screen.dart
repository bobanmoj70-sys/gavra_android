import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/v2_pumpa_punjenje.dart';
import '../models/v2_pumpa_stanje.dart';
import '../models/v2_pumpa_tocenje.dart';
import '../models/v2_vozilo_statistika.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_gorivo_service.dart';
import '../services/v2_pumpa_service.dart';
import '../services/v2_vozila_service.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';

/// > GORIVO SCREEN
/// Kucna pumpa — stanje, punjenja, tocenja, statistike po vozilu
class V2GorivoScreen extends StatefulWidget {
  const V2GorivoScreen({super.key});

  @override
  State<V2GorivoScreen> createState() => _GorivoScreenState();
}

class _GorivoScreenState extends State<V2GorivoScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const Color _accent = Color(0xFFFF9800); // narandžasta = gorivo

  final _fmt = NumberFormat('#,##0.0', 'sr');
  final _fmtInt = NumberFormat('#,###', 'sr');

  /// Stream koji emituje kad se bilo koja od ove 4 tabele promijeni u cache-u
  late final Stream<_GorivoData> _stream;

  /// Filter za statistike — od prvog dana tekućeg meseca
  final DateTime _statsOd = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _stream = V2MasterRealtimeManager.instance.v2StreamFromCache<_GorivoData>(
      tables: ['v2_pumpa_config', 'v2_pumpa_punjenja', 'v2_pumpa_tocenja', 'v2_vozila'],
      build: _buildGorivoData,
    ).asBroadcastStream();
  }

  _GorivoData _buildGorivoData() {
    return _GorivoData(
      stanje: V2GorivoService.getStanjeSync(),
      punjenja: V2PumpaPunjenjaService.getPunjenjaSync(),
      tocenja: V2PumpaTocenjaService.getTocenjaSync(),
      statistike: _getStatistikeSync(_statsOd),
    );
  }

  List<V2VoziloStatistika> _getStatistikeSync(DateTime od) {
    final odStr = od.toIso8601String().split('T')[0];
    final rm = V2MasterRealtimeManager.instance;
    final Map<String, V2VoziloStatistika> mapa = {};
    for (final r in rm.tocenjaCache.values) {
      final d = r['datum']?.toString() ?? '';
      if (d.compareTo(odStr) < 0) continue;
      final voziloId = r['vozilo_id']?.toString() ?? '';
      final litri = (r['litri'] as num?)?.toDouble() ?? 0.0;
      final voziloRow = rm.vozilaCache[voziloId];
      final regBroj = voziloRow?['registarski_broj']?.toString() ?? voziloId;
      final marka = voziloRow?['marka']?.toString() ?? '';
      final model = voziloRow?['model']?.toString() ?? '';
      final existing = mapa[voziloId];
      if (existing != null) {
        mapa[voziloId] = existing.copyWith(
          ukupnoLitri: existing.ukupnoLitri + litri,
          brojTocenja: existing.brojTocenja + 1,
        );
      } else {
        mapa[voziloId] = V2VoziloStatistika(
          voziloId: voziloId,
          registarskiBroj: regBroj,
          marka: marka,
          model: model,
          ukupnoLitri: litri,
          brojTocenja: 1,
        );
      }
    }
    final lista = mapa.values.toList();
    lista.sort((a, b) => b.ukupnoLitri.compareTo(a.ukupnoLitri));
    return lista;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_GorivoData>(
      stream: _stream,
      initialData: _buildGorivoData(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? _buildGorivoData();
        return _buildScaffold(context, data);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, _GorivoData data) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: Theme.of(context).backgroundGradient,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).glassBorder),
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.local_gas_station, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Pumpa goriva',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54)],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showConfigDialog,
            tooltip: 'Podesi pumpu',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: '⛽ Stanje'),
            Tab(text: '🛢️ Punjenja'),
            Tab(text: '🚗 Točenja'),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: Theme.of(context).backgroundGradient),
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildStanjeTab(data),
            _buildPunjenjaTab(data.punjenja),
            _buildTocenjaTab(data.tocenja),
          ],
        ),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildFab() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        if (_tabController.index == 1) {
          return FloatingActionButton.extended(
            onPressed: _showDodajPunjenjeDialog,
            backgroundColor: Colors.green,
            icon: const Icon(Icons.add),
            label: const Text('Punjenje'),
          );
        } else if (_tabController.index == 2) {
          return FloatingActionButton.extended(
            onPressed: _showDodajTocenjeDialog,
            backgroundColor: _accent,
            icon: const Icon(Icons.local_gas_station),
            label: const Text('Točenje'),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildStanjeTab(_GorivoData data) {
    final stanje = data.stanje;
    if (stanje == null) {
      return const Center(child: Text('Konfiguracija pumpe nije pronađena'));
    }
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + kToolbarHeight + 48 + 16, 16, 16),
      child: Column(
        children: [
          _buildBrojcanik(stanje),
          const SizedBox(height: 16),
          _buildStanjeDetalji(stanje),
          const SizedBox(height: 16),
          _buildStatistikePoVozilu(data.statistike),
        ],
      ),
    );
  }

  /// Vizuelni brojčanik pumpe
  Widget _buildBrojcanik(V2PumpaStanje stanje) {
    final procenat = (stanje.procenatPune / 100).clamp(0.0, 1.0);
    final Color barColor = stanje.prazna
        ? Colors.grey
        : stanje.ispodAlarma
            ? Colors.red
            : procenat > 0.6
                ? Colors.green
                : Colors.orange;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: barColor.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(color: barColor.withValues(alpha: 0.15), blurRadius: 16, spreadRadius: 1),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '⛽ Trenutno stanje',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                if (stanje.ispodAlarma)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red),
                    ),
                    child: const Text(
                      '⚠️ MALO GORIVA',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Veliki broj litara
            Text(
              '${_fmt.format(stanje.trenutnoStanje)} L',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
            Text(
              'od ${_fmt.format(stanje.kapacitetLitri)} L kapaciteta',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: procenat,
                minHeight: 24,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('0 L', style: TextStyle(color: Colors.white38, fontSize: 12)),
                Text(
                  '${stanje.procenatPune.toStringAsFixed(0)}%',
                  style: TextStyle(fontWeight: FontWeight.bold, color: barColor),
                ),
                Text('${_fmt.format(stanje.kapacitetLitri)} L',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStanjeDetalji(V2PumpaStanje stanje) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Detalji',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 12),
            _detaljiRow('🟢 Ukupno dopunjeno', '${_fmt.format(stanje.ukupnoPunjeno)} L', Colors.greenAccent),
            _detaljiRow('🔴 Ukupno utrošeno', '${_fmt.format(stanje.ukupnoUtroseno)} L', Colors.redAccent),
            _detaljiRow(
              '🔔 Alarm nivo',
              '${_fmt.format(stanje.alarmNivo)} L',
              stanje.ispodAlarma ? Colors.redAccent : Colors.white54,
            ),
            _detaljiRow(
              '📦 Kapacitet',
              '${_fmt.format(stanje.kapacitetLitri)} L',
              Colors.white70,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _detaljiRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: valueColor, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatistikePoVozilu(List<V2VoziloStatistika> lista) {
    if (lista.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📊 Potrošnja ovog meseca po vozilu',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 12),
            ...lista.map((v) => _statVoziloRow(v, lista.first.ukupnoLitri)),
          ],
        ),
      ),
    );
  }

  Widget _statVoziloRow(V2VoziloStatistika v, double max) {
    final ratio = max > 0 ? (v.ukupnoLitri / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(v.registarskiBroj, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '${_fmt.format(v.ukupnoLitri)} L · ${v.brojTocenja}× točeno',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunjenjaTab(List<V2PumpaPunjenje> lista) {
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_gas_station, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Nema zabeleženih punjenja',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    )),
            const SizedBox(height: 8),
            const Text('Klikni + da dodaš prvo punjenje', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + kToolbarHeight + 48 + 12, 12, 80),
      itemCount: lista.length,
      itemBuilder: (context, i) => _buildPunjenjeCard(lista[i]),
    );
  }

  Widget _buildPunjenjeCard(V2PumpaPunjenje p) {
    final datumStr = DateFormat('dd.MM.yyyy', 'sr').format(p.datum);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.4), width: 1.5),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.withValues(alpha: 0.15),
          child: const Text('🛢️', style: TextStyle(fontSize: 20)),
        ),
        title: Text(
          '+${_fmt.format(p.litri)} L',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 18),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(datumStr),
            if (p.cenaPoPLitru != null)
              Text(
                '${_fmt.format(p.cenaPoPLitru!)} din/L · ${_fmtInt.format(p.ukupnoCena ?? (p.litri * p.cenaPoPLitru!))} din',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            if (p.napomena != null) Text(p.napomena!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _confirmDelete(
            'Obriši punjenje?',
            '${_fmt.format(p.litri)} L od $datumStr',
            () async {
              await V2GorivoService.deletePunjenje(p.id);
              // Stream se automatski osvježava kroz RM Realtime event
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTocenjaTab(List<V2PumpaTocenje> lista) {
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('Nema zabeleženih točenja',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    )),
            const SizedBox(height: 8),
            const Text('Klikni + da dodaš točenje', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + kToolbarHeight + 48 + 12, 12, 80),
      itemCount: lista.length,
      itemBuilder: (context, i) => _buildTocenjeCard(lista[i]),
    );
  }

  Widget _buildTocenjeCard(V2PumpaTocenje t) {
    final datumStr = DateFormat('dd.MM.yyyy', 'sr').format(t.datum);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _accent.withValues(alpha: 0.15),
          child: const Text('🚗', style: TextStyle(fontSize: 20)),
        ),
        title: Row(
          children: [
            Text(
              '-${_fmt.format(t.litri)} L',
              style: const TextStyle(fontWeight: FontWeight.bold, color: _accent, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                t.voziloNaziv,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(datumStr),
            if (t.kmVozila != null)
              Text(
                '${_fmtInt.format(t.kmVozila!)} km',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            if (t.napomena != null) Text(t.napomena!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _confirmDelete(
            'Obriši točenje?',
            '${_fmt.format(t.litri)} L — ${t.voziloNaziv} — $datumStr',
            () async {
              await V2GorivoService.deleteTocenje(t.id);
              // Stream se automatski osvježava kroz RM Realtime event
            },
          ),
        ),
      ),
    );
  }

  void _showDodajPunjenjeDialog() {
    final litriCtrl = TextEditingController();
    final cenaCtrl = TextEditingController();
    final napomenaCtrl = TextEditingController();
    DateTime datum = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => _buildBottomSheet(
          title: '🛢️ Novo punjenje pumpe',
          accentColor: Colors.green,
          children: [
            _datumRow(datum, (d) => setLocal(() => datum = d)),
            const SizedBox(height: 12),
            _inputField(litriCtrl, 'Litri *', suffixText: 'L', keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _inputField(cenaCtrl, 'Cena po litru', suffixText: 'din/L', keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _inputField(napomenaCtrl, 'Napomena'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final litri = double.tryParse(litriCtrl.text.replaceAll(',', '.'));
                  if (litri == null || litri <= 0) {
                    V2AppSnackBar.warning(context, 'Unesi broj litara!');
                    return;
                  }
                  final litriVal = litri;
                  final cenaVal = double.tryParse(cenaCtrl.text.replaceAll(',', '.'));
                  final napomenaVal = napomenaCtrl.text.isEmpty ? null : napomenaCtrl.text;
                  final ok = await V2GorivoService.addPunjenje(
                    datum: datum,
                    litri: litriVal,
                    cenaPoPLitru: cenaVal,
                    napomena: napomenaVal,
                  );
                  if (!context.mounted) return;
                  litriCtrl.dispose();
                  cenaCtrl.dispose();
                  napomenaCtrl.dispose();
                  Navigator.pop(ctx);
                  if (ok) {
                    // Stream se automatski osvježava kroz RM Realtime event
                    V2AppSnackBar.success(context, '✅ Punjenje dodato: $litriVal L');
                  } else {
                    V2AppSnackBar.error(context, '❌ Greška pri dodavanju');
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Dodaj punjenje'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDodajTocenjeDialog() async {
    final vozila = V2VozilaService.getVozila();
    if (!mounted) return;

    final litriCtrl = TextEditingController();
    final kmCtrl = TextEditingController();
    final napomenaCtrl = TextEditingController();
    DateTime datum = DateTime.now();
    V2Vozilo? selectedVozilo = vozila.isNotEmpty ? vozila.first : null;

    final lastCena = await V2GorivoService.getPoslednaCenaPoPLitru();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => _buildBottomSheet(
          title: '🚗 Novo točenje',
          accentColor: _accent,
          children: [
            _datumRow(datum, (d) => setLocal(() => datum = d)),
            const SizedBox(height: 12),
            DropdownButtonFormField<V2Vozilo>(
              value: selectedVozilo,
              decoration: _inputDeco('Vozilo *'),
              items: vozila
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          '${v.registarskiBroj}${v.marka != null ? " - ${v.marka}" : ""}',
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setLocal(() => selectedVozilo = v),
            ),
            const SizedBox(height: 12),
            _inputField(litriCtrl, 'Litri *', suffixText: 'L', keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _inputField(kmCtrl, 'Km vozila', suffixText: 'km', keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _inputField(napomenaCtrl, 'Napomena'),
            if (lastCena != null) ...[
              const SizedBox(height: 8),
              Text(
                'Poslednja cena: ${lastCena.toStringAsFixed(2)} din/L — koristi se za finansije',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final litri = double.tryParse(litriCtrl.text.replaceAll(',', '.'));
                  if (litri == null || litri <= 0) {
                    V2AppSnackBar.warning(context, 'Unesi broj litara!');
                    return;
                  }
                  final vozilo = selectedVozilo;
                  if (vozilo == null) {
                    V2AppSnackBar.warning(context, 'Izaberi vozilo!');
                    return;
                  }
                  final litriVal = litri;
                  final kmVal = int.tryParse(kmCtrl.text.replaceAll(',', '.'));
                  final napomenaVal = napomenaCtrl.text.isEmpty ? null : napomenaCtrl.text;
                  final ok = await V2GorivoService.addTocenje(
                    datum: datum,
                    voziloId: vozilo.id,
                    litri: litriVal,
                    kmVozila: kmVal,
                    napomena: napomenaVal,
                    cenaPoPLitru: lastCena,
                  );
                  if (!context.mounted) return;
                  litriCtrl.dispose();
                  kmCtrl.dispose();
                  napomenaCtrl.dispose();
                  Navigator.pop(ctx);
                  if (ok) {
                    // Stream se automatski osvježava kroz RM Realtime event
                    V2AppSnackBar.success(context, '✅ Točenje zabeleženo: $litriVal L — ${vozilo.registarskiBroj}');
                  } else {
                    V2AppSnackBar.error(context, '❌ Greška pri dodavanju');
                  }
                },
                icon: const Icon(Icons.local_gas_station),
                label: const Text('Zabeleži točenje'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConfigDialog() {
    final config = V2MasterRealtimeManager.instance.pumpaCache.values.firstOrNull;

    final kapacitetCtrl =
        TextEditingController(text: ((config?['kapacitet_litri'] as num?)?.toStringAsFixed(0)) ?? '3000');
    final alarmCtrl = TextEditingController(text: ((config?['alarm_nivo'] as num?)?.toStringAsFixed(0)) ?? '500');
    final pocetnoCtrl = TextEditingController(text: ((config?['pocetno_stanje'] as num?)?.toStringAsFixed(0)) ?? '0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildBottomSheet(
        title: '⚙️ Podešavanja pumpe',
        accentColor: Colors.blueGrey,
        children: [
          _inputField(kapacitetCtrl, 'Kapacitet pumpe', suffixText: 'L', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _inputField(alarmCtrl, 'Alarm — upozorenje ispod', suffixText: 'L', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _inputField(pocetnoCtrl, 'Početno stanje (koliko ima sad)',
              suffixText: 'L', keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          Text(
            'Početno stanje postavi na trenutnu litrazu pumpe. Sve buduće promene idu na to.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final kapacitetVal = double.tryParse(kapacitetCtrl.text.replaceAll(',', '.'));
                final alarmVal = double.tryParse(alarmCtrl.text.replaceAll(',', '.'));
                final pocetnoVal = double.tryParse(pocetnoCtrl.text.replaceAll(',', '.'));
                final ok = await V2GorivoService.updateConfig(
                  kapacitet: kapacitetVal,
                  alarmNivo: alarmVal,
                  pocetnoStanje: pocetnoVal,
                );
                if (!context.mounted) return;
                kapacitetCtrl.dispose();
                alarmCtrl.dispose();
                pocetnoCtrl.dispose();
                Navigator.pop(ctx);
                if (ok) {
                  // Stream se automatski osvježava kada RM primi Realtime event za v2_pumpa_config
                  V2AppSnackBar.success(context, '✅ Podešavanja sačuvana');
                } else {
                  V2AppSnackBar.error(context, '❌ Greška pri čuvanju');
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Sačuvaj'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String title, String subtitle, VoidCallback onConfirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(subtitle),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Otkaži')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Obriši', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) onConfirm();
  }

  static Widget _buildBottomSheet({
    required String title,
    required Color accentColor,
    required List<Widget> children,
  }) {
    return Builder(
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _datumRow(DateTime datum, ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: datum,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _inputDeco('Datum'),
        child: Text(
          DateFormat('dd.MM.yyyy', 'sr').format(datum),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static Widget _inputField(
    TextEditingController ctrl,
    String label, {
    String? suffixText,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: _inputDeco(label, suffixText: suffixText),
    );
  }

  static InputDecoration _inputDeco(String label, {String? suffixText}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffixText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

/// Snapshot svih gorivo podataka za jedan StreamBuilder rebuild
class _GorivoData {
  final V2PumpaStanje? stanje;
  final List<V2PumpaPunjenje> punjenja;
  final List<V2PumpaTocenje> tocenja;
  final List<V2VoziloStatistika> statistike;

  const _GorivoData({
    required this.stanje,
    required this.punjenja,
    required this.tocenja,
    required this.statistike,
  });
}
