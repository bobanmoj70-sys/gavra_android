import 'package:flutter/material.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_statistika_service.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_style_helper.dart';

class V3PutnikStatistikaScreen extends StatefulWidget {
  final String putnikId;
  final String imePrezime;
  final String tipPutnika;

  const V3PutnikStatistikaScreen({
    super.key,
    required this.putnikId,
    required this.imePrezime,
    required this.tipPutnika,
  });

  @override
  State<V3PutnikStatistikaScreen> createState() => _V3PutnikStatistikaScreenState();
}

class _V3PutnikStatistikaScreenState extends State<V3PutnikStatistikaScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance
          .tablesRevisionStream(const ['v3_operativna_nedelja', 'v3_finansije', 'v3_auth']),
      builder: (context, _) {
        final godina = DateTime.now().year;
        final meseci = V3PutnikStatistikaService.getZaGodinu(widget.putnikId, godina: godina);
        final ukupnoVoznji = meseci.fold<int>(0, (sum, mesec) => sum + mesec.ukupnoVoznji);
        final ukupnaObaveza = meseci.fold<double>(0.0, (sum, mesec) => sum + mesec.ukupnaObaveza);
        final ukupnoPlaceno = meseci.fold<double>(0.0, (sum, mesec) => sum + mesec.naplacenoIznos);
        final ukupanDug = meseci.fold<double>(0.0, (sum, mesec) => sum + mesec.dugIznos);

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            title: const Text('Detaljne statistike', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    V3ContainerUtils.styledContainer(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: V3StyleHelper.whiteAlpha06,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: V3StyleHelper.whiteAlpha13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.imePrezime,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tipLabel(widget.tipPutnika),
                            style:
                                TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Prikaz po mesecima (januar-decembar $godina)',
                            style: TextStyle(color: V3StyleHelper.whiteAlpha65, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    V3ContainerUtils.styledContainer(
                      padding: const EdgeInsets.all(14),
                      backgroundColor: V3StyleHelper.whiteAlpha06,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: V3StyleHelper.whiteAlpha13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Godišnji obračun',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          _summaryRow('Godina', '$godina', Colors.white),
                          _summaryRow('Ukupan broj vožnji', '$ukupnoVoznji', Colors.greenAccent),
                          _summaryRow('Ukupna obaveza', '${ukupnaObaveza.toStringAsFixed(0)} RSD', Colors.amberAccent),
                          _summaryRow('Ukupno plaćeno', '${ukupnoPlaceno.toStringAsFixed(0)} RSD', Colors.greenAccent),
                          _summaryRow('Ukupan dug', '${ukupanDug.toStringAsFixed(0)} RSD', Colors.orangeAccent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...meseci.map((m) => _MesecCard(stats: m)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _tipLabel(String tip) {
    final normalized = tip.toLowerCase();
    if (normalized == 'radnik') return 'Tip: Radnik (model po danu)';
    if (normalized == 'ucenik') return 'Tip: Učenik (model po danu)';
    if (normalized == 'posiljka') return 'Tip: Pošiljka (model po vožnji)';
    return 'Tip: Dnevni (model po vožnji)';
  }

  Widget _summaryRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MesecCard extends StatelessWidget {
  final V3PutnikMesecnaStatistika stats;

  const _MesecCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      backgroundColor: V3StyleHelper.whiteAlpha06,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: V3StyleHelper.whiteAlpha13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stats.mesecNaziv} ${stats.godina}',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniKpi(label: 'Realiz.', value: '${stats.pokupljeno}', color: Colors.lightBlueAccent),
              _MiniKpi(label: 'Vožnji', value: '${stats.ukupnoVoznji}', color: Colors.greenAccent),
              _MiniKpi(label: 'Otkazano', value: '${stats.otkazano}', color: Colors.redAccent),
            ],
          ),
          const SizedBox(height: 10),
          if (stats.cena > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Obaveza', style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
                Text(
                  '${stats.ukupnoVoznji} × ${stats.cena.toStringAsFixed(0)} = ${stats.ukupnaObaveza.toStringAsFixed(0)} RSD',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
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
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dug (${stats.neplaceno})', style: TextStyle(color: V3StyleHelper.whiteAlpha75, fontSize: 13)),
              Text(
                '${stats.dugIznos.toStringAsFixed(0)} RSD',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniKpi({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return V3ContainerUtils.styledContainer(
      width: 90,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
}
