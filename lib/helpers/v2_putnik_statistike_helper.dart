import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v2_registrovani_putnik.dart';
import '../services/realtime/v2_master_realtime_manager.dart';
import '../services/v2_polasci_service.dart';

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

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.analytics_outlined, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Detaljne statistike - $putnikIme',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // DROPDOWN ZA PERIOD
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedPeriod,
                          isExpanded: true,
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: Colors.blue.shade600,
                          ),
                          items: _getMonthOptions().map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: Colors.blue.shade300,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(value),
                                ],
                              ),
                            );
                          }).toList()
                            ..addAll([
                              // CELA GODINA I UKUPNO
                              DropdownMenuItem(
                                value: 'Cela ${DateTime.now().year}',
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.event_note,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Cela ${DateTime.now().year}'),
                                  ],
                                ),
                              ),
                              const DropdownMenuItem(
                                value: 'Ukupno',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.history,
                                      size: 16,
                                      color: Colors.purple,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Ukupno'),
                                  ],
                                ),
                              ),
                            ]),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                selectedPeriod = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    FutureBuilder<Map<String, dynamic>>(
                      future: _getStatistikeForPeriod(putnikId, selectedPeriod, tip),
                      builder: (context, snapshot) {
                        // Loading state
                        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
                          return const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        if (snapshot.hasError) {
                          return const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()),
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
                                  const Icon(
                                    Icons.warning_amber_outlined,
                                    color: Colors.orange,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Podaci trenutno nisu dostupni.\nPovežite se na internet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.orange[700]),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return _buildStatistikeContent(
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Zatvori'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // DOHVATI PLAĆENE MESECE ZA PUTNIKA
  static Future<Set<String>> _getPlaceniMeseci(String putnikId) async {
    try {
      final svaPlacanja = await V2PutnikStatistikaService.dohvatiPlacanja(putnikId);
      final Set<String> placeni = {};

      for (var placanje in svaPlacanja) {
        final mesec = placanje['placeni_mesec'];
        final godina = placanje['placena_godina'];
        if (mesec != null && godina != null) {
          placeni.add('$mesec-$godina');
        }
      }
      return placeni;
    } catch (e) {
      return {};
    }
  }

  // KREIRANJE SADRŽAJA STATISTIKA
  static Widget _buildStatistikeContent({
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📋 Osnovne informacije',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              _buildStatRow('👤 Ime:', putnikIme),
              _buildStatRow('📊 Tip putnika:', tip),
              if (tipSkole != null)
                _buildStatRow(
                  tip == 'ucenik' ? '🏫 Škola:' : '🏢 Ustanova/Firma:',
                  tipSkole,
                ),
              if (brojTelefona != null) _buildStatRow('📞 Telefon:', brojTelefona),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // FINANSIJSKE INFORMACIJE
        _buildFinancialSection(putnikId, tip, stats['cena_po_danu']),

        const SizedBox(height: 16),

        // PLAĆENI MESECI
        _buildPlaceniMeseciSection(tip, stats['placeniMeseci'] ?? {}),

        const SizedBox(height: 16),

        // STATISTIKE PUTOVANJA - DINAMICKI PERIOD
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: periodColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: periodColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(periodIcon, size: 16, color: periodColor),
                  const SizedBox(width: 4),
                  Text(
                    '📈 Statistike',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: periodColor,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildStatRow('🚗 Putovanja:', '${stats['putovanja'] ?? 0}'),
              _buildStatRow('❌ Otkazivanja:', '${stats['otkazivanja'] ?? 0}'),
              _buildStatRow(
                '🔄 Poslednje putovanje:',
                stats['poslednje'] as String? ?? 'Nema podataka',
              ),
              _buildStatRow('📊 Uspešnost:', '${stats['uspesnost'] ?? 0}%'),
              if (stats['ukupan_prihod'] != null)
                _buildStatRow(
                  '💰 Ukupan prihod:',
                  '${stats['ukupan_prihod']}',
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // SISTEMSKE INFORMACIJE
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🕐 Sistemske informacije',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              _buildStatRow('📅 Kreiran:', _formatDatum(createdAt)),
              _buildStatRow('🔄 Ažuriran:', _formatDatum(updatedAt)),
              _buildStatRow('✅ Status:', aktivan ? 'Aktivan' : 'Neaktivan'),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildFinancialSection(String putnikId, String tip, dynamic customCena) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💰 Finansijske informacije',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green[700],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          // PRIKAZ CENE PO DANU
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🏷️ Vaša cena:',
                style: TextStyle(
                  color: Colors.green[900],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                (customCena != null && customCena > 0)
                    ? '${(customCena as num).toStringAsFixed(0)} RSD / ${tip.toLowerCase() == 'radnik' || tip.toLowerCase() == 'ucenik' ? 'dan' : 'vožnja'}'
                    : 'Cena nije postavljena',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const Divider(),
          // Datum, iznos i vozač poslednjeg plaćanja
          FutureBuilder<Map<String, dynamic>?>(
            future: V2PutnikStatistikaService.dohvatiPlacanja(putnikId).then((l) => l.isNotEmpty ? l.first : null),
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
                  _buildStatRow(
                    '📅 Datum plaćanja:',
                    datum ?? 'Nema podataka o datumu',
                  ),
                  _buildStatRow('🚗 Vozač (naplata):', vozacIme ?? 'Nema podataka'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _buildPlaceniMeseciSection(String tip, Set<String> placeniMeseci) {
    if (tip.toLowerCase() == 'dnevni' || tip.toLowerCase() == 'posiljka') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: const Text(
          '💡 Dnevni putnici i pošiljke plaćaju po pokupljenju. Detalji su prikazani u istoriji ispod.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💰 Plaćeni meseci',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green[700],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: placeniMeseci.isEmpty
                ? [const Text('Nema evidentiranih uplata', style: TextStyle(fontSize: 12))]
                : placeniMeseci.map((m) {
                    return Chip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.green.shade100,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
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
    return '${_getMonthName(now.month)} ${now.year}';
  }

  static List<String> _getMonthOptions() {
    final now = DateTime.now();
    List<String> options = [];
    for (int month = 1; month <= 12; month++) {
      options.add('${_getMonthName(month)} ${now.year}');
    }
    return options;
  }

  static String _getMonthName(int month) {
    const months = [
      '',
      'Januar',
      'Februar',
      'Mart',
      'April',
      'Maj',
      'Jun',
      'Jul',
      'Avgust',
      'Septembar',
      'Oktobar',
      'Novembar',
      'Decembar',
    ];
    return months[month];
  }

  static int _getMonthNumber(String monthName) {
    const months = [
      '',
      'Januar',
      'Februar',
      'Mart',
      'April',
      'Maj',
      'Jun',
      'Jul',
      'Avgust',
      'Septembar',
      'Oktobar',
      'Novembar',
      'Decembar',
    ];
    for (int i = 1; i < months.length; i++) {
      if (months[i] == monthName) {
        return i;
      }
    }
    return 0;
  }

  static Future<Map<String, dynamic>> _getStatistikeForPeriod(String putnikId, String period, String tipPutnika) async {
    try {
      final placeniMeseci = await _getPlaceniMeseci(putnikId);
      final putnikMap = await V2MasterRealtimeManager.instance.findPutnikById(putnikId);
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
            final monthNumber = _getMonthNumber(monthName);
            if (monthNumber > 0) {
              stats = await _getStatistikeZaMesec(putnikId, monthNumber, year, tipPutnika);
            }
          }
        }
      }

      if (stats.isEmpty) stats = _emptyStats();
      stats['placeniMeseci'] = placeniMeseci;
      stats['cena_po_danu'] = putnikObj?.cena;
      return stats;
    } catch (e) {
      return {'error': true, ..._emptyStats()};
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
    } catch (e) {
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
  static Map<String, dynamic> _emptyStats() {
    return {
      'putovanja': 0,
      'otkazivanja': 0,
      'poslednje': 'Nema podataka',
      'uspesnost': 0,
    };
  }
}
