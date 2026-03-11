import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_statistika_istorija_service.dart';
import '../theme.dart';
import '../utils/v2_dan_utils.dart';

/// Helper za prikazivanje detaljnih statistika putnika
/// Koristi se i u admin ekranu i u profilu putnika
class V2PutnikStatistikeHelper {
  V2PutnikStatistikeHelper._();

  /// Prikaži dijalog sa detaljnim statistikama
  static Future<void> prikaziDetaljneStatistike({
    required BuildContext context,
    required String putnikId,
    required String putnikIme,
    required String tip,
    String? tipSkole,
    String? brojTelefona,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool aktivan = true,
  }) async {
    String selectedPeriod = _getCurrentMonthYear();

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.95,
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                decoration: BoxDecoration(
                  gradient: Theme.of(context).backgroundGradient,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).glassBorder, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── HEADER ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                        border: Border(
                          bottom: BorderSide(color: Theme.of(context).glassBorder),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                            ),
                            child: const Icon(Icons.analytics_outlined, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Detaljne statistike',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  putnikIme,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.of(dialogContext).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── SCROLLABLE CONTENT ──
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // DROPDOWN ZA PERIOD
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                border: Border.all(color: Theme.of(context).glassBorder),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedPeriod,
                                  isExpanded: true,
                                  dropdownColor: Theme.of(context).backgroundGradient.colors.first,
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                                  items: _getMonthOptions().map<DropdownMenuItem<String>>((String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today, size: 14, color: Colors.white54),
                                          const SizedBox(width: 8),
                                          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                        ],
                                      ),
                                    );
                                  }).toList()
                                    ..addAll([
                                      DropdownMenuItem(
                                        value: 'Cela ${DateTime.now().year}',
                                        child: Builder(
                                          builder: (context) {
                                            final currentYear = DateTime.now().year;
                                            return Row(
                                              children: [
                                                const Icon(Icons.event_note, size: 14, color: Colors.lightBlueAccent),
                                                const SizedBox(width: 8),
                                                Text('Cela $currentYear',
                                                    style: const TextStyle(color: Colors.white, fontSize: 14)),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      const DropdownMenuItem(
                                        value: 'Ukupno',
                                        child: Row(
                                          children: [
                                            Icon(Icons.history, size: 14, color: Colors.purpleAccent),
                                            SizedBox(width: 8),
                                            Text('Ukupno', style: TextStyle(color: Colors.white, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ]),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() => selectedPeriod = newValue);
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            FutureBuilder<Map<String, dynamic>>(
                              future: _getStatistikeForPeriod(putnikId, selectedPeriod, tip),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
                                  return const SizedBox(
                                    height: 200,
                                    child: Center(
                                      child: CircularProgressIndicator(color: Colors.white54),
                                    ),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return const SizedBox(
                                    height: 200,
                                    child: Center(
                                      child: Text(
                                        'Greška pri učitavanju statistika.',
                                        style: TextStyle(color: Colors.redAccent, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                }
                                final stats = snapshot.data ?? {};
                                if (stats['error'] == true) {
                                  return SizedBox(
                                    height: 200,
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(50),
                                            ),
                                            child: const Icon(Icons.wifi_off_outlined, color: Colors.orange, size: 40),
                                          ),
                                          const SizedBox(height: 14),
                                          const Text(
                                            'Podaci nisu dostupni.\nPovežite se na internet.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.orange, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return _buildStatistikeContent(
                                  context: context,
                                  putnikIme: putnikIme,
                                  tip: tip,
                                  tipSkole: tipSkole,
                                  brojTelefona: brojTelefona,
                                  createdAt: createdAt,
                                  updatedAt: updatedAt,
                                  aktivan: aktivan,
                                  putnikId: putnikId,
                                  stats: stats,
                                  period: selectedPeriod,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // DOHVATI PLAĆENE MESECE ZA PUTNIKA
  static Future<Set<String>> _getPlaceniMeseci(String putnikId) async {
    try {
      final svaPlacanja = await V2StatistikaIstorijaService.dohvatiPlacanja(putnikId);
      final Set<String> placeni = {};

      for (var placanje in svaPlacanja) {
        final mesec = placanje['placeni_mesec'];
        final godina = placanje['placena_godina'];
        if (mesec != null && godina != null) {
          placeni.add('$mesec-$godina');
        }
      }
      return placeni;
    } catch (e, st) {
      debugPrint('[V2PutnikStatistikeHelper] _getPlaceniMeseci greška: $e\n$st');
      return {};
    }
  }

  // KREIRANJE SADRŽAJA STATISTIKA
  static Widget _buildStatistikeContent({
    required BuildContext context,
    required String putnikIme,
    required String tip,
    String? tipSkole,
    String? brojTelefona,
    DateTime? createdAt,
    DateTime? updatedAt,
    required bool aktivan,
    required String putnikId,
    required Map<String, dynamic> stats,
    required String period,
  }) {
    Color periodColor = Colors.orange;
    IconData periodIcon = Icons.calendar_today;

    if (period.startsWith('Cela ')) {
      periodColor = Colors.blue;
      periodIcon = Icons.event_note;
    } else if (period == 'Ukupno') {
      periodColor = Colors.purple;
      periodIcon = Icons.history;
    }

    return Column(
      children: [
        // OSNOVNE INFORMACIJE
        _buildSection(
          context: context,
          accentColor: Colors.blue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('📋 Osnovne informacije', Colors.blue),
              const SizedBox(height: 8),
              _buildStatRow('👤 Ime:', putnikIme),
              if (tipSkole != null)
                _buildStatRow(
                  tip == 'ucenik' ? '🏫 Škola:' : '🏢 Ustanova/Firma:',
                  tipSkole,
                ),
              if (brojTelefona != null) _buildStatRow('📞 Telefon:', brojTelefona),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // FINANSIJSKE INFORMACIJE
        _buildFinancialSection(context, putnikId, tip, stats['cena_po_danu']),

        const SizedBox(height: 12),

        // PLAĆENI MESECI
        _buildPlaceniMeseciSection(context, tip, stats['placeniMeseci'] ?? {}),

        const SizedBox(height: 12),

        // STATISTIKE PUTOVANJA - DINAMIČKI PERIOD
        _buildSection(
          context: context,
          accentColor: periodColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(periodIcon, size: 15, color: periodColor),
                  const SizedBox(width: 6),
                  Text(
                    '📈 Statistike putovanja',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: periodColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildStatRow('🚗 Putovanja:', '${stats['putovanja'] ?? 0}'),
              _buildStatRow('❌ Otkazivanja:', '${stats['otkazivanja'] ?? 0}'),
              _buildStatRow(
                '🔄 Poslednje:',
                stats['poslednje'] as String? ?? 'Nema podataka',
              ),
              _buildStatRow('📊 Uspešnost:', '${stats['uspesnost'] ?? 0}%'),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // SISTEMSKE INFORMACIJE
        _buildSection(
          context: context,
          accentColor: Colors.white24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('🕐 Sistemske informacije', Colors.white54),
              _buildStatRow('📅 Kreiran:', _formatDatum(createdAt)),
              _buildStatRow('🔄 Ažuriran:', _formatDatum(updatedAt)),
              _buildStatRow('✅ Status:', aktivan ? 'Aktivan' : '⚠️ Neaktivan'),
            ],
          ),
        ),
      ],
    );
  }

  // HELPER: Sekcija kontejner
  static Widget _buildSection({
    required BuildContext context,
    required Color accentColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.25), width: 1),
      ),
      child: child,
    );
  }

  // HELPER: Sekcija naslov
  static Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 14,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Widget _buildFinancialSection(BuildContext context, String putnikId, String tip, dynamic customCena) {
    return _buildSection(
      context: context,
      accentColor: Colors.greenAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('💰 Finansijske informacije', Colors.greenAccent),
          // PRIKAZ CENE PO DANU
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🏷️ Vaša cena:',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 13),
              ),
              Flexible(
                child: Text(
                  (customCena != null && customCena > 0)
                      ? '${(customCena as num).toStringAsFixed(0)} RSD / ${tip.toLowerCase() == 'radnik' || tip.toLowerCase() == 'ucenik' ? 'dan' : 'vožnja'}'
                      : 'Nije postavljena',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 20),
          // Datum, iznos i vozač poslednjeg plaćanja
          FutureBuilder<Map<String, dynamic>?>(
            future: V2StatistikaIstorijaService.dohvatiPlacanja(putnikId).then((l) => l.isNotEmpty ? l.first : null),
            builder: (context, snapshot) {
              final placanje = snapshot.data;
              final datum = placanje?['datum'] as String?;
              final vozacIme = placanje?['vozac_ime'] as String?;
              final iznos = (placanje?['iznos'] as num?)?.toDouble() ?? 0.0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatRow(
                    '💵 Poslednje plaćanje:',
                    iznos > 0 ? '${iznos.toStringAsFixed(0)} RSD' : 'Nema podataka',
                  ),
                  _buildStatRow('📅 Datum plaćanja:', datum ?? 'Nema podataka'),
                  _buildStatRow('🚗 Vozač (naplata):', vozacIme ?? 'Nema podataka'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _buildPlaceniMeseciSection(BuildContext context, String tip, Set<String> placeniMeseci) {
    if (tip.toLowerCase() == 'dnevni' || tip.toLowerCase() == 'posiljka') {
      return _buildSection(
        context: context,
        accentColor: Colors.blueAccent,
        child: const Text(
          '💡 Dnevni putnici i pošiljke plaćaju po pokupljenju.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white70),
        ),
      );
    }

    return _buildSection(
      context: context,
      accentColor: Colors.greenAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('✅ Plaćeni meseci', Colors.greenAccent),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: placeniMeseci.isEmpty
                ? [
                    const Text(
                      'Nema evidentiranih uplata',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    )
                  ]
                : placeniMeseci.map((m) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                      ),
                      child: Text(m,
                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
                    );
                  }).toList(),
          ),
        ],
      ),
    );
  }

  // HELPER METODA ZA KREIRANJE REDA STATISTIKE
  static Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDatum(DateTime? datum) {
    if (datum == null) return 'Nema podataka';
    return '${datum.day}.${datum.month}.${datum.year}';
  }

  static String _getCurrentMonthYear() {
    final now = DateTime.now();
    return '${V2DanUtils.mesecNaziv(now.month)} ${now.year}';
  }

  static List<String> _getMonthOptions() {
    final now = DateTime.now();
    List<String> options = [];
    for (int month = 1; month <= 12; month++) {
      options.add('${V2DanUtils.mesecNaziv(month)} ${now.year}');
    }
    return options;
  }

  static Future<Map<String, dynamic>> _getStatistikeForPeriod(String putnikId, String period, String tipPutnika) async {
    try {
      final placeniMeseci = await _getPlaceniMeseci(putnikId);
      final putnikMap = await V2MasterRealtimeManager.instance.v2FindPutnikById(putnikId);
      final putnikObj = putnikMap != null ? V2RegistrovaniPutnik.fromMap(putnikMap) : null;

      Map<String, dynamic> stats = {};

      if (period.startsWith('Cela ')) {
        stats = await _getGodisnjeStatistike(putnikId, tipPutnika);
      } else if (period == 'Ukupno') {
        stats = await _getUkupneStatistike(putnikId, tipPutnika);
      } else {
        // Parsiraj mesec
        final parts = period.split(' ');
        if (parts.length == 2) {
          final monthName = parts[0];
          final year = int.tryParse(parts[1]);
          if (year != null) {
            final monthNumber = V2DanUtils.mesecBroj(monthName);
            if (monthNumber > 0) {
              stats = await _getStatistikeZaMesec(putnikId, monthNumber, year, tipPutnika);
            }
          }
        }
      }

      if (stats.isEmpty) stats = Map<String, dynamic>.from(_kEmptyStats);
      stats['placeniMeseci'] = placeniMeseci;
      stats['cena_po_danu'] = putnikObj?.cena;
      return stats;
    } catch (e, st) {
      debugPrint('[V2PutnikStatistikeHelper] _getStatistikeForPeriod greška: $e\n$st');
      return {'error': true, ..._kEmptyStats};
    }
  }

  static Future<Map<String, dynamic>> _getGodisnjeStatistike(String putnikId, String tipPutnika) async {
    final currentYear = DateTime.now().year;
    final startOfYearStr = '$currentYear-01-01';
    final endOfYearStr = '$currentYear-12-31';

    final tp = tipPutnika.toLowerCase();
    final bool jeDnevni = tp.contains('dnevni') || tp.contains('posiljka') || tp.contains('pošiljka');

    final response = await supabase
        .from('v2_statistika_istorija')
        .select('id, tip, datum, iznos, broj_mesta, created_at')
        .eq('putnik_id', putnikId)
        .gte('datum', startOfYearStr)
        .lte('datum', endOfYearStr)
        .order('datum', ascending: false);

    Map<String, int> dailyMaxVoznje = {};
    Map<String, int> dailyMaxOtkazivanja = {};
    String? poslednje;
    double ukupanPrihod = 0;

    for (final record in response) {
      final tip = record['tip'] as String?;
      final double iznos = ((record['iznos'] ?? 0) as num).toDouble();
      final String? datum = record['datum'] as String?;
      final int bm = (record['broj_mesta'] as num?)?.toInt() ?? 1;

      if (tip == 'voznja' && datum != null) {
        ukupanPrihod += iznos;
        if (jeDnevni) {
          // Za dnevne sabiramo svako sedište (transakciono)
          final uniqueKey = record['id']?.toString() ?? (datum + (record['created_at']?.toString() ?? ''));
          dailyMaxVoznje[uniqueKey] = bm;
        } else {
          // Za radnike/učenike uzimamo max broj mesta u toku dana
          if (bm > (dailyMaxVoznje[datum] ?? 0)) {
            dailyMaxVoznje[datum] = bm;
          }
        }

        if (poslednje == null) {
          try {
            final d = DateTime.parse(datum);
            poslednje = '${d.day}/${d.month}/${d.year}';
          } catch (_) {
            poslednje = datum;
          }
        }
      } else if (tip == 'otkazivanje' && datum != null) {
        if (jeDnevni) {
          final uniqueKey = record['id']?.toString() ?? (datum + (record['created_at']?.toString() ?? ''));
          dailyMaxOtkazivanja[uniqueKey] = bm;
        } else {
          if (bm > (dailyMaxOtkazivanja[datum] ?? 0)) {
            dailyMaxOtkazivanja[datum] = bm;
          }
        }
      }
    }

    int putovanja = 0;
    dailyMaxVoznje.forEach((k, v) => putovanja += v);

    int otkazivanjaData = 0;
    dailyMaxOtkazivanja.forEach((key, v) {
      if (jeDnevni) {
        otkazivanjaData += v;
      } else {
        if (!dailyMaxVoznje.containsKey(key)) {
          otkazivanjaData += v;
        }
      }
    });

    final ukupno = putovanja + otkazivanjaData;
    final uspesnost = ukupno > 0 ? ((putovanja / ukupno) * 100).round() : 0;

    return {
      'putovanja': putovanja,
      'otkazivanja': otkazivanjaData,
      'poslednje': poslednje ?? 'Nema podataka',
      'uspesnost': uspesnost,
      'ukupan_prihod': '${ukupanPrihod.toStringAsFixed(0)} RSD',
    };
  }

  static Future<Map<String, dynamic>> _getUkupneStatistike(String putnikId, String tipPutnika) async {
    final response = await supabase
        .from('v2_statistika_istorija')
        .select('id, tip, datum, iznos, broj_mesta, created_at')
        .eq('putnik_id', putnikId)
        .order('datum', ascending: false);

    Map<String, int> dailyMaxVoznje = {};
    Map<String, int> dailyMaxOtkazivanja = {};
    String? poslednje;
    double ukupanPrihod = 0;

    final tp = tipPutnika.toLowerCase();
    final bool jeDnevni = tp.contains('dnevni') || tp.contains('posiljka') || tp.contains('pošiljka');

    for (final record in response) {
      final tip = record['tip'] as String?;
      final double iznos = ((record['iznos'] ?? 0) as num).toDouble();
      final String? datum = record['datum'] as String?;
      final int bm = (record['broj_mesta'] as num?)?.toInt() ?? 1;

      if (tip == 'voznja' && datum != null) {
        ukupanPrihod += iznos;
        if (jeDnevni) {
          final uniqueKey = record['id']?.toString() ?? (datum + (record['created_at']?.toString() ?? ''));
          dailyMaxVoznje[uniqueKey] = bm;
        } else {
          if (bm > (dailyMaxVoznje[datum] ?? 0)) {
            dailyMaxVoznje[datum] = bm;
          }
        }

        if (poslednje == null) {
          try {
            final d = DateTime.parse(datum);
            poslednje = '${d.day}/${d.month}/${d.year}';
          } catch (_) {
            poslednje = datum;
          }
        }
      } else if (tip == 'otkazivanje' && datum != null) {
        if (jeDnevni) {
          final uniqueKey = record['id']?.toString() ?? (datum + (record['created_at']?.toString() ?? ''));
          dailyMaxOtkazivanja[uniqueKey] = bm;
        } else {
          if (bm > (dailyMaxOtkazivanja[datum] ?? 0)) {
            dailyMaxOtkazivanja[datum] = bm;
          }
        }
      }
    }

    int putovanja = 0;
    dailyMaxVoznje.forEach((k, v) => putovanja += v);

    int otkazivanjaData = 0;
    dailyMaxOtkazivanja.forEach((key, v) {
      if (jeDnevni) {
        otkazivanjaData += v;
      } else {
        if (!dailyMaxVoznje.containsKey(key)) {
          otkazivanjaData += v;
        }
      }
    });

    final ukupno = putovanja + otkazivanjaData;
    final uspesnost = ukupno > 0 ? ((putovanja / ukupno) * 100).round() : 0;

    return {
      'putovanja': putovanja,
      'otkazivanja': otkazivanjaData,
      'poslednje': poslednje ?? 'Nema podataka',
      'uspesnost': uspesnost,
      'ukupan_prihod': '${ukupanPrihod.toStringAsFixed(0)} RSD',
    };
  }

  /// DOHVATI DETALJNE STATISTIKE ZA MESEC
  static Future<Map<String, dynamic>> _getStatistikeZaMesec(
      String putnikId, int mesec, int godina, String tipPutnika) async {
    try {
      final startOfMonthStr = "$godina-${mesec.toString().padLeft(2, '0')}-01";
      final lastDay = DateTime(godina, mesec + 1, 0).day;
      final endOfMonthStr = "$godina-${mesec.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}";

      final tp = tipPutnika.toLowerCase();
      final bool jeDnevni = tp.contains('dnevni') || tp.contains('posiljka') || tp.contains('pošiljka');

      final response = await supabase
          .from('v2_statistika_istorija')
          .select('id, tip, datum, iznos, broj_mesta, created_at')
          .eq('putnik_id', putnikId)
          .gte('datum', startOfMonthStr)
          .lte('datum', endOfMonthStr)
          .order('datum', ascending: false);

      final voznje = List<Map<String, dynamic>>.from(response);

      double ukupanPrihodData = 0;
      Map<String, int> dailyMaxVoznje = {};
      Map<String, int> dailyMaxOtkazivanja = {};
      String? poslednjiDatum;

      for (final voznja in voznje) {
        final tip = voznja['tip'] as String?;
        final double iznos = ((voznja['iznos'] ?? 0) as num).toDouble();
        final String? datum = voznja['datum'] as String?;
        final int bm = (voznja['broj_mesta'] as num?)?.toInt() ?? 1;

        if (tip == 'voznja' && datum != null) {
          ukupanPrihodData += iznos;
          if (jeDnevni) {
            final uniqueKey = voznja['id']?.toString() ?? (datum + (voznja['created_at']?.toString() ?? ''));
            dailyMaxVoznje[uniqueKey] = bm;
          } else {
            if (bm > (dailyMaxVoznje[datum] ?? 0)) {
              dailyMaxVoznje[datum] = bm;
            }
          }
          poslednjiDatum ??= datum;
        } else if (tip == 'otkazivanje' && datum != null) {
          if (jeDnevni) {
            final uniqueKey = voznja['id']?.toString() ?? (datum + (voznja['created_at']?.toString() ?? ''));
            dailyMaxOtkazivanja[uniqueKey] = bm;
          } else {
            if (bm > (dailyMaxOtkazivanja[datum] ?? 0)) {
              dailyMaxOtkazivanja[datum] = bm;
            }
          }
        }
      }

      int brojPutovanja = 0;
      dailyMaxVoznje.forEach((k, v) => brojPutovanja += v);

      int brojOtkazivanja = 0;
      dailyMaxOtkazivanja.forEach((key, v) {
        if (jeDnevni) {
          brojOtkazivanja += v;
        } else {
          if (!dailyMaxVoznje.containsKey(key)) {
            brojOtkazivanja += v;
          }
        }
      });

      return {
        'putovanja': brojPutovanja,
        'otkazivanja': brojOtkazivanja,
        'poslednje': poslednjiDatum ?? 'Nema podataka',
        'uspesnost': (brojPutovanja + brojOtkazivanja) > 0
            ? ((brojPutovanja / (brojPutovanja + brojOtkazivanja)) * 100).round()
            : 0,
        'ukupan_prihod': '${ukupanPrihodData.toStringAsFixed(0)} RSD',
      };
    } catch (e, st) {
      debugPrint('[V2PutnikStatistikeHelper] _getStatistikeZaMesec greška: $e\n$st');
      return {
        'error': true,
        'putovanja': 0,
        'otkazivanja': 0,
        'poslednje': 'Greška',
        'uspesnost': 0,
        'ukupan_prihod': '0 RSD'
      };
    }
  }

  /// DOHVATI MEDICINSKU POMOĆ LOGS - dodato kao fensi opcija
  static const Map<String, dynamic> _kEmptyStats = {
    'putovanja': 0,
    'otkazivanja': 0,
    'poslednje': 'Nema podataka',
    'uspesnost': 0,
  };
}
