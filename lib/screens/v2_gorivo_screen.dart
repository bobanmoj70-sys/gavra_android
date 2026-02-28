?import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/v2_gorivo_service.dart';
import '../services/v2_vozila_service.dart';
import '../utils/v2_app_snack_bar.dart';

/// �>� GORIVO SCREEN
/// Ku�?na pumpa �?" stanje, punjenja, točenja, statistike po vozilu
class GorivoScreen extends StatefulWidget {
  const GorivoScreen({super.key});

  @override
  State<GorivoScreen> createState() => _GorivoScreenState();
}

class _GorivoScreenState extends State<GorivoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const Color _accent = Color(0xFFFF9800); // narandžasta = gorivo

  final _fmt = NumberFormat('#,##0.0', 'sr');
  final _fmtInt = NumberFormat('#,###', 'sr');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('�>� Pumpa goriva', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: _accent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showConfigDialog,
            tooltip: 'Podesi pumpu',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '�Y"S Stanje'),
            Tab(text: '�Y>�️ Punjenja'),
            Tab(text: '�Ys- Točenja'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStanjeTab(),
          _buildPunjenjaTab(),
          _buildTocenjaTab(),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  // �"?�"? FAB - mijenja se po tabu �"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?
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

  // �"?�"? TAB 1: STANJE �"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?
  Widget _buildStanjeTab() {
    return FutureBuilder<PumpaStanje?>(
      future: V2GorivoService.getStanje(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        final stanje = snapshot.data;
        if (stanje == null) {
          return const Center(child: Text('Greška pri učitavanju stanja'));
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          color: _accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildBrojcanik(stanje),
                const SizedBox(height: 16),
                _buildStanjeDetalji(stanje),
                const SizedBox(height: 16),
                _buildStatistikePoVozilu(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Vizuelni brojčanik pumpe
  Widget _buildBrojcanik(PumpaStanje stanje) {
    final procenat = (stanje.procenatPune / 100).clamp(0.0, 1.0);
    final Color barColor = stanje.prazna
        ? Colors.grey
        : stanje.ispodAlarma
            ? Colors.red
            : procenat > 0.6
                ? Colors.green
                : Colors.orange;

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: barColor.withOpacity(0.6), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '�>� Trenutno stanje',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (stanje.ispodAlarma)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red),
                    ),
                    child: const Text(
                      '�s�️ MALO GORIVA',
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
            ),
            const SizedBox(height: 20),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: procenat,
                minHeight: 24,
                backgroundColor: Colors.grey.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 L',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        )),
                Text(
                  '${stanje.procenatPune.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: barColor,
                  ),
                ),
                Text('${_fmt.format(stanje.kapacitetLitri)} L',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStanjeDetalji(PumpaStanje stanje) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('�Y"< Detalji',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 12),
            _detaljiRow('�YY� Ukupno dopunjeno', '${_fmt.format(stanje.ukupnoPunjeno)} L', Colors.green),
            _detaljiRow('�Y"� Ukupno utrošeno', '${_fmt.format(stanje.ukupnoUtroseno)} L', Colors.red),
            _detaljiRow(
              '�Y"" Alarm nivo',
              '${_fmt.format(stanje.alarmNivo)} L',
              stanje.ispodAlarma ? Colors.red : Colors.grey,
            ),
            _detaljiRow(
              '�Y"� Kapacitet',
              '${_fmt.format(stanje.kapacitetLitri)} L',
              Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _detaljiRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  )),
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  )),
        ],
      ),
    );
  }

  Widget _buildStatistikePoVozilu() {
    return FutureBuilder<List<VoziloStatistika>>(
      future: V2GorivoService.getStatistikePoVozilu(
        od: DateTime(DateTime.now().year, DateTime.now().month, 1),
      ),
      builder: (context, snapshot) {
        final lista = snapshot.data ?? [];
        if (lista.isEmpty) return const SizedBox.shrink();

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('�Ys- Potrošnja ovog meseca �?" po vozilu',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
                const SizedBox(height: 12),
                ...lista.map((v) => _statVoziloRow(v, lista.first.ukupnoLitri)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statVoziloRow(VoziloStatistika v, double max) {
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
                '${_fmt.format(v.ukupnoLitri)} L  �?�  ${v.brojTocenja}�- točeno',
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
              backgroundColor: Colors.grey.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            ),
          ),
        ],
      ),
    );
  }

  // �"?�"? TAB 2: PUNJENJA �"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?
  Widget _buildPunjenjaTab() {
    return FutureBuilder<List<PumpaPunjenje>>(
      future: V2GorivoService.getPunjenja(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        final lista = snapshot.data ?? [];
        if (lista.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.local_gas_station, size: 64, color: Colors.grey.withOpacity(0.3)),
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
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          color: _accent,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: lista.length,
            itemBuilder: (context, i) => _buildPunjenjeCard(lista[i]),
          ),
        );
      },
    );
  }

  Widget _buildPunjenjeCard(PumpaPunjenje p) {
    final datumStr = DateFormat('dd.MM.yyyy', 'sr').format(p.datum);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withOpacity(0.4), width: 1.5),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.withOpacity(0.15),
          child: const Text('�Y>�️', style: TextStyle(fontSize: 20)),
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
                '${_fmt.format(p.cenaPoPLitru!)} din/L  �?'  ${_fmtInt.format(p.ukupnoCena ?? 0)} din',
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
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  // �"?�"? TAB 3: TO�OENJA �"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?
  Widget _buildTocenjaTab() {
    return FutureBuilder<List<PumpaTocenje>>(
      future: V2GorivoService.getTocenja(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        final lista = snapshot.data ?? [];
        if (lista.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.directions_car, size: 64, color: Colors.grey.withOpacity(0.3)),
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
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          color: _accent,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: lista.length,
            itemBuilder: (context, i) => _buildTocenjeCard(lista[i]),
          ),
        );
      },
    );
  }

  Widget _buildTocenjeCard(PumpaTocenje t) {
    final datumStr = DateFormat('dd.MM.yyyy', 'sr').format(t.datum);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _accent.withOpacity(0.4), width: 1.5),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _accent.withOpacity(0.15),
          child: const Text('�>�', style: TextStyle(fontSize: 20)),
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
            '${_fmt.format(t.litri)} L �?" ${t.voziloNaziv} �?" $datumStr',
            () async {
              await V2GorivoService.deleteTocenje(t.id);
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  // �"?�"? DIJALOZI �"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?

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
          title: '�Y>�️ Novo punjenje pumpe',
          accentColor: Colors.green,
          children: [
            // Datum
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
                  final litri = double.tryParse(litriCtrl.text);
                  if (litri == null || litri <= 0) {
                    AppSnackBar.warning(context, 'Unesi broj litara!');
                    return;
                  }
                  final ok = await V2GorivoService.addPunjenje(
                    datum: datum,
                    litri: litri,
                    cenaPoPLitru: double.tryParse(cenaCtrl.text),
                    napomena: napomenaCtrl.text.isEmpty ? null : napomenaCtrl.text,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  if (ok) setState(() {});
                  if (ok) {
                    AppSnackBar.success(context, '�o. Punjenje dodato: $litri L');
                  } else {
                    AppSnackBar.error(context, '�O Greška pri dodavanju');
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

  void _showDodajTocenjeDialog() async {
    final vozila = await V2VozilaService.getVozila();
    if (!mounted) return;

    final litriCtrl = TextEditingController();
    final kmCtrl = TextEditingController();
    final napomenaCtrl = TextEditingController();
    DateTime datum = DateTime.now();
    Vozilo? selectedVozilo = vozila.isNotEmpty ? vozila.first : null;

    // Zadnja cijena
    final lastCena = await V2GorivoService.getPoslednaCenaPoPLitru();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => _buildBottomSheet(
          title: '�>� Novo točenje',
          accentColor: _accent,
          children: [
            // Datum
            _datumRow(datum, (d) => setLocal(() => datum = d)),
            const SizedBox(height: 12),

            // Vozilo dropdown
            DropdownButtonFormField<Vozilo>(
              value: selectedVozilo,
              decoration: _inputDeco('Vozilo *'),
              items: vozila
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          '${v.registarskiBroj}${v.marka != null ? " �?" ${v.marka}" : ""}',
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
                'Poslednja cena: ${lastCena.toStringAsFixed(2)} din/L �?" koristi se za finansije',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final litri = double.tryParse(litriCtrl.text);
                  if (litri == null || litri <= 0) {
                    AppSnackBar.warning(context, 'Unesi broj litara!');
                    return;
                  }
                  if (selectedVozilo == null) {
                    AppSnackBar.warning(context, 'Izaberi vozilo!');
                    return;
                  }
                  final ok = await V2GorivoService.addTocenje(
                    datum: datum,
                    voziloId: selectedVozilo!.id,
                    litri: litri,
                    kmVozila: int.tryParse(kmCtrl.text),
                    napomena: napomenaCtrl.text.isEmpty ? null : napomenaCtrl.text,
                    cenaPoPLitru: lastCena,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  if (ok) setState(() {});
                  if (ok) {
                    AppSnackBar.success(
                        context, '�o. Točenje zabeleženo: $litri L �?' ${selectedVozilo!.registarskiBroj}');
                  } else {
                    AppSnackBar.error(context, '�O Greška pri dodavanju');
                  }
                },
                icon: const Icon(Icons.local_gas_station),
                label: const Text('Zabeloži točenje'),
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

  void _showConfigDialog() async {
    final stanje = await V2GorivoService.getStanje();
    if (!mounted) return;

    final kapacitetCtrl = TextEditingController(text: stanje?.kapacitetLitri.toStringAsFixed(0) ?? '3000');
    final alarmCtrl = TextEditingController(text: stanje?.alarmNivo.toStringAsFixed(0) ?? '500');
    final pocetnoCtrl = TextEditingController(text: stanje?.pocetnoStanje.toStringAsFixed(0) ?? '0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildBottomSheet(
        title: '�sT️ Podešavanja pumpe',
        accentColor: Colors.blueGrey,
        children: [
          _inputField(kapacitetCtrl, 'Kapacitet pumpe', suffixText: 'L', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _inputField(alarmCtrl, 'Alarm �?" upozorenje ispod', suffixText: 'L', keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _inputField(pocetnoCtrl, 'Početno stanje (koliko ima sad)',
              suffixText: 'L', keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          Text(
            'Početno stanje postavi na trenutnu litražu pumpe. Sve budu�?e promene idu na to.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final ok = await V2GorivoService.updateConfig(
                  kapacitet: double.tryParse(kapacitetCtrl.text),
                  alarmNivo: double.tryParse(alarmCtrl.text),
                  pocetnoStanje: double.tryParse(pocetnoCtrl.text),
                );
                if (!context.mounted) return;
                Navigator.pop(ctx);
                if (ok) setState(() {});
                if (ok) {
                  AppSnackBar.success(context, '�o. podešavanja sačuvana');
                } else {
                  AppSnackBar.error(context, '�O Greška pri čuvanju');
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
    if (ok == true) onConfirm();
  }

  // �"?�"? HELPERS �"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?�"?

  Widget _buildBottomSheet({
    required String title,
    required Color accentColor,
    required List<Widget> children,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
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

  Widget _inputField(
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

  InputDecoration _inputDeco(String label, {String? suffixText}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffixText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
