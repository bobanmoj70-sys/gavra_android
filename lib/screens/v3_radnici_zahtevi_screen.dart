// ignore_for_file: unused_element, unused_import

import 'package:flutter/material.dart';

import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_putnik_service.dart';
import '../services/v3_locale_manager.dart';
import '../theme.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_dan_helper.dart';
import '../utils/v3_status_policy.dart';
import '../utils/v3_string_utils.dart';
import '../widgets/v3_zahtev_timelapse_widget.dart';

class _RadZahTr {
  static const Map<String, Map<String, String>> _t = {
    'monitoringZahteva': {
      'sr': 'Monitoring zahteva',
      'en': 'Request monitoring',
      'ru': 'Мониторинг запросов',
      'de': 'Anfragenüberwachung'
    },
    'obrada': {'sr': 'obrada', 'en': 'processing', 'ru': 'обработка', 'de': 'Bearbeitung'},
    'odobreno': {'sr': 'odobreno', 'en': 'approved', 'ru': 'одобрено', 'de': 'genehmigt'},
    'odbijeno': {'sr': 'odbijeno', 'en': 'rejected', 'ru': 'отклонено', 'de': 'abgelehnt'},
    'otkazano': {'sr': 'otkazano', 'en': 'canceled', 'ru': 'отменено', 'de': 'storniert'},
    'nemaZahteva': {'sr': 'Nema zahteva', 'en': 'No requests', 'ru': 'Нет запросов', 'de': 'Keine Anfragen'},
    'putnik': {'sr': 'Putnik', 'en': 'Passenger', 'ru': 'Пассажир', 'de': 'Fahrgast'},
  };

  static String tr(String key) {
    final code = V3LocaleManager().currentLocale.languageCode;
    return _t[key]?[code] ?? _t[key]?['sr'] ?? key;
  }
}

/// V3 ekran — Monitoring zahteva radnika.
class V3RadniciZahteviScreen extends StatefulWidget {
  const V3RadniciZahteviScreen({super.key});

  @override
  State<V3RadniciZahteviScreen> createState() => _V3RadniciZahteviScreenState();
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class _V3RadniciZahteviScreenState extends State<V3RadniciZahteviScreen> {
  static const String _sistemAkterId = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e';

  bool _isSistemAkter(String? akterId, Map<String, Map<String, dynamic>> authCache) {
    final id = (akterId ?? '').trim();
    if (id.isEmpty) return false;
    if (id == _sistemAkterId) return true;
    final tip = (authCache[id]?['tip']?.toString() ?? '').trim().toLowerCase();
    return tip == 'sistem';
  }

  List<Map<String, dynamic>> _getMonitoringZahteviRaw() {
    final rm = V3MasterRealtimeManager.instance;
    const tip = 'radnik';

    final putniciIds = rm.putniciCache.values
        .where((p) => (p['tip_putnika'] as String? ?? '').toLowerCase() == tip)
        .map((p) => p['id'] as String)
        .toSet();

    return rm.zahteviCache.values.where((r) {
      final createdBy = (r['created_by']?.toString() ?? '').trim();
      if (createdBy.isEmpty) return false;
      // Prikazujemo zahteve kreirane od strane radnika (kron ih samo obrađuje, ne kreira)
      final isRadnik = putniciIds.contains(createdBy);
      if (!isRadnik) return false;

      final datumRaw = r['datum']?.toString();
      final datum = datumRaw != null ? DateTime.tryParse(datumRaw) : null;
      if (datum == null) return false;
      if (!V3DanHelper.isInSchedulingWeek(datum)) return false;

      final status = (r['status']?.toString() ?? '').trim().toLowerCase();
      if (V3StatusPolicy.isCanceled(status)) {
        final updatedBy = (r['updated_by']?.toString() ?? '').trim();
        if (updatedBy.isEmpty) return false;
        if (updatedBy != createdBy && !_isSistemAkter(updatedBy, rm.authCache)) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) {
        final aCreated = DateTime.tryParse((a['created_at']?.toString() ?? '')) ?? DateTime(2000);
        final bCreated = DateTime.tryParse((b['created_at']?.toString() ?? '')) ?? DateTime(2000);
        final createdCmp = bCreated.compareTo(aCreated);
        if (createdCmp != 0) return createdCmp;
        final aDatum = DateTime.tryParse((a['datum']?.toString() ?? '')) ?? DateTime(2000);
        final bDatum = DateTime.tryParse((b['datum']?.toString() ?? '')) ?? DateTime(2000);
        return bDatum.compareTo(aDatum);
      });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: V3MasterRealtimeManager.instance.tablesRevisionStream(const ['v3_auth', 'v3_zahtevi']),
      builder: (context, _) {
        final zahteviRaw = _getMonitoringZahteviRaw();
        final obrada = zahteviRaw.where((z) {
          final status = (z['status']?.toString() ?? '').trim();
          return V3StatusPolicy.isPending(status) || V3StatusPolicy.isOfferLike(status);
        }).length;
        final odobreno = zahteviRaw.where((z) => V3StatusPolicy.isApproved(z['status']?.toString())).length;
        final odbijeno = zahteviRaw.where((z) => V3StatusPolicy.isRejected(z['status']?.toString())).length;
        final otkazano = zahteviRaw.where((z) => V3StatusPolicy.isCanceled(z['status']?.toString())).length;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            title: Text(
              _RadZahTr.tr('monitoringZahteva'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: V3ContainerUtils.backgroundContainer(
            gradient: Theme.of(context).backgroundGradient,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        if (obrada > 0) _badge('🟡 $obrada ${_RadZahTr.tr('obrada')}', Colors.amber),
                        if (odobreno > 0) _badge('🟢 $odobreno ${_RadZahTr.tr('odobreno')}', Colors.greenAccent),
                        if (odbijeno > 0) _badge('🔴 $odbijeno ${_RadZahTr.tr('odbijeno')}', Colors.redAccent),
                        if (otkazano > 0) _badge('⛔ $otkazano ${_RadZahTr.tr('otkazano')}', Colors.orange),
                        if (zahteviRaw.isEmpty)
                          Text(
                            _RadZahTr.tr('nemaZahteva'),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: zahteviRaw.isEmpty
                        ? Center(
                            child: Text(
                              _RadZahTr.tr('nemaZahteva'),
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                            physics: const BouncingScrollPhysics(),
                            itemCount: zahteviRaw.length,
                            itemBuilder: (_, i) => _MonitoringCardRadnik(row: zahteviRaw[i]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _badge(String tekst, Color color) => V3ContainerUtils.badgeContainer(
        backgroundColor: color.withValues(alpha: 0.15),
        borderColor: color.withValues(alpha: 0.5),
        borderWidth: 1,
        child: Text(tekst, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _MonitoringCardRadnik extends StatelessWidget {
  const _MonitoringCardRadnik({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = row['status']?.toString() ?? '';
    final style = V3StatusPolicy.statusCardStyle(status);
    final borderColor = style.borderColor;
    final statusLabel = style.label;
    final putnikId = (row['created_by']?.toString() ?? '').trim();
    final putnik = V3PutnikService.getPutnikById(putnikId);
    final zahtev = V3Zahtev.fromJson(row);

    return V3ContainerUtils.iconContainer(
      margin: const EdgeInsets.only(bottom: 8),
      backgroundColor: borderColor.withValues(alpha: 0.06),
      borderRadiusGeometry: BorderRadius.circular(14),
      border: Border.all(color: borderColor.withValues(alpha: 0.45), width: 1.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            V3ContainerUtils.iconContainer(
              backgroundColor: borderColor.withValues(alpha: 0.15),
              borderRadius: 10,
              icon: Icon(Icons.monitor_heart_outlined, color: borderColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          putnik?.imePrezime ?? _RadZahTr.tr('putnik'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      Text(statusLabel, style: TextStyle(color: borderColor, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${zahtev.grad} · ${V3StringUtils.trimTimeToHhMm(zahtev.trazeniPolazakAt)} · ${V3DanHelper.label(zahtev.datum)} · ${zahtev.datum.day}.${zahtev.datum.month}.${zahtev.datum.year}.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  V3ZahtevTimelapseWidget(zahtev: zahtev),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
