import 'package:flutter/material.dart';

import '../config/v2_route_config.dart';
import '../globals.dart';
import '../services/v2_theme_manager.dart';
import '../utils/v2_app_snack_bar.dart';

/// UNIVERZALNI TIME PICKER CELL WIDGET
/// Koristi se za prikaz i izbor vremena polaska (BC ili VS)
///
/// Koristi se na:
/// - Dodaj putnika (RegistrovaniPutnikDialog)
/// - Uredi putnika (RegistrovaniPutnikDialog)
/// - Moj profil učenici (RegistrovaniPutnikProfilScreen)
/// - Moj profil radnici (RegistrovaniPutnikProfilScreen)
class V2TimePickerCell extends StatelessWidget {
  final String? value;
  final bool isBC;
  final ValueChanged<String?> onChanged;
  final double? width;
  final double? height;
  final String? status; // obrada, odobreno, otkazano, odbijeno, pokupljen
  final String? dayName; // Dan u nedelji (pon, uto, sre...) za zaključavanje prošlih dana
  final String? tipPutnika; // Tip putnika: radnik, ucenik, dnevni
  final String? tipPrikazivanja; // Režim prikaza: standard, DNEVNI
  final DateTime? datumKrajaMeseca; // Datum do kog je plaćeno

  const V2TimePickerCell({
    super.key,
    required this.value,
    required this.isBC,
    required this.onChanged,
    this.width = 70,
    this.height = 40,
    this.status,
    this.dayName,
    this.tipPutnika,
    this.tipPrikazivanja,
    this.datumKrajaMeseca,
  });

  // ─────────────────────────────────────────────────────────────────
  // CENTRALNA LOGIKA ZAKLJUČAVANJA
  // Pravilo: ćelija je zaključana ako je trenutno vreme >= vreme polaska
  // za taj dan u AKTIVNOJ nedelji.
  // Aktivna nedelja:
  // - sub >= 02:00 ili ned → pon-pet su u SLEDEĆOJ kalendarskoj nedelji
  // - inače               → pon-pet su u TEKUĆOJ kalendarskoj nedelji
  // Jedna metoda (_resolvePolazakDateTime) vraća tačan DateTime polaska.
  // Sve ostale metode koriste samo nju.
  // ─────────────────────────────────────────────────────────────────

  /// Vraća tačan DateTime polaska za ovaj widget (dan + vreme).
  /// Ako [vreme] nije prosleđen, koristi [value].
  /// Vraća null ako dayName ili vreme nisu dostupni/parsabilni.
  DateTime? _resolvePolazakDateTime({String? vreme}) {
    final v = vreme ?? value;
    if (dayName == null) return null;

    final now = DateTime.now();

    const daniMap = {'pon': 1, 'uto': 2, 'sre': 3, 'cet': 4, 'pet': 5, 'sub': 6, 'ned': 7};
    final targetWeekday = daniMap[dayName!.toLowerCase()];
    if (targetWeekday == null) return null;

    // Aktivna nedelja: sub >= 02:00 ili ned → sledeća nedelja
    final jeNovaNedelja = (now.weekday == 6 && now.hour >= 2) || now.weekday == 7;

    // Nađi ponedeljak aktivne nedelje
    late DateTime monday;
    if (jeNovaNedelja) {
      // Sledeći ponedeljak
      final daysToMonday = 8 - now.weekday; // sub(6)→2, ned(7)→1
      monday = DateTime(now.year, now.month, now.day).add(Duration(days: daysToMonday));
    } else {
      // Ponedeljak tekuće nedelje
      monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    }

    final dayDate = monday.add(Duration(days: targetWeekday - 1));

    // Ako nema vremena, vraćamo samo datum (bez sata) — za isLocked provjeru
    if (v == null || v.isEmpty) return dayDate;

    try {
      final parts = v.split(':');
      if (parts.length < 2) return dayDate;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return DateTime(dayDate.year, dayDate.month, dayDate.day, h, m);
    } catch (_) {
      return dayDate;
    }
  }

  /// Ćelija je zaključana ako je vreme polaska nastupilo (now >= polazak).
  /// Bez vrednosti vremena: zaključano ako je dan u prošlosti.
  bool get isLocked {
    if (tipPutnika == 'posiljka') return false;
    if (dayName == null) return false;

    final polazak = _resolvePolazakDateTime();
    if (polazak == null) return false;

    final now = DateTime.now();

    if (value == null || value!.isEmpty) {
      // Nema zakazanog vremena — zaključano samo ako je dan prošao
      final dayOnly = DateTime(polazak.year, polazak.month, polazak.day);
      final todayOnly = DateTime(now.year, now.month, now.day);
      return dayOnly.isBefore(todayOnly);
    }

    // Ima zakazano vreme — zaključano čim nastupi vreme polaska
    return now.isAtSameMomentAs(polazak) || now.isAfter(polazak);
  }

  /// Da li je vreme polaska (value) nastupilo — alias za isLocked kada ima vrednost.
  bool _isTimePassed() => isLocked;

  /// Da li je specifično vreme u listi pickera već prošlo.
  bool _isSpecificTimePassed(String vreme) {
    if (dayName == null) return false;
    final polazak = _resolvePolazakDateTime(vreme: vreme);
    if (polazak == null) return false;
    final now = DateTime.now();
    return now.isAtSameMomentAs(polazak) || now.isAfter(polazak);
  }

  @override
  Widget build(BuildContext context) {
    final hasTime = value != null && value!.isNotEmpty;
    final isObrada = status == 'obrada';
    final isOdobreno = status == 'odobreno';
    final isOtkazano = status == 'otkazano';
    final isOdbijeno = status == 'odbijeno';
    final locked = isLocked;

    // Boje za različite statuse
    Color borderColor = Colors.grey.shade300;
    Color bgColor = Colors.white;
    Color textColor = Colors.black87;

    // OTKAZANO - crvena (prioritet nad svim ostalim)
    if (isOtkazano) {
      borderColor = Colors.red;
      bgColor = Colors.red.shade50;
      textColor = Colors.red.shade800;
    }
    // ODBIJENO - plava
    else if (isOdbijeno) {
      borderColor = Colors.blue;
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade900;
    }
    // ⬜ PROŠLI DAN - sivo
    else if (locked) {
      borderColor = Colors.grey.shade400;
      bgColor = Colors.grey.shade200;
      textColor = Colors.grey.shade600;
    }
    // ODOBRENO - zelena
    else if (isOdobreno) {
      borderColor = Colors.green;
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade800;
    }
    // OBRADA - narandžasta
    else if (isObrada) {
      borderColor = Colors.orange;
      bgColor = Colors.orange.shade200;
      textColor = Colors.orange.shade900;
    }
    // IMA VREMENA - zelena
    else if (hasTime) {
      borderColor = Colors.green;
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade800;
    }

    return GestureDetector(
      onTap: () async {
        // Omogućavamo otkazanim terminima da se ponovo aktiviraju ukoliko vreme nije prošlo
        if (isOtkazano && _isTimePassed()) return;

        // VREME POLASKA JE NASTUPILO
        if (_isTimePassed()) {
          V2AppSnackBar.warning(context, '🔒 Vreme polaska je nastupilo. Izmene nisu moguće do subote.');
          return;
        }

        final now = DateTime.now();

        // BLOKADA ZA OBRADA STATUS
        if (isObrada && hasTime) {
          V2AppSnackBar.warning(context, '⏳ Vaš zahtev za ovo vreme je već u obradi. Molimo sačekajte odgovor.');
          return;
        }

        // BLOKADA ZA ODBIJENO STATUS
        if (isOdbijeno) {
          V2AppSnackBar.error(context, '❌ Ovaj termin je popunjen. Izaberite neko drugo slobodno vreme.');
          return;
        }

        // EKSPLICITNA PORUKA DNEVNIM PUTNICIMA AKO JE ZAKLJUČANO
        if ((tipPutnika == 'dnevni' || tipPrikazivanja == 'DNEVNI') && isLocked) {
          V2AppSnackBar.blocked(context,
              'Zbog optimizacije kapaciteta, rezervacije za dnevne putnike su moguće samo za tekući dan i sutrašnji dan. Hvala na razumevanju! 🚌');
          return;
        }

        if (locked) {
          final msg = hasTime
              ? '🔒 Vreme polaska je nastupilo. Izmene nisu moguće do subote.'
              : '🔒 Zakazivanje za ovo vreme je prošlo. Od subote kreće novi ciklus.';
          V2AppSnackBar.warning(context, msg);
          return;
        }

        // PROVERA ZA DNEVNE PUTNIKE - samo danas i sutra
        if (tipPutnika == 'dnevni' || tipPrikazivanja == 'DNEVNI') {
          final now = DateTime.now();
          final todayOnly = DateTime(now.year, now.month, now.day);
          final tomorrowOnly = todayOnly.add(const Duration(days: 1));
          final dayDate = _resolvePolazakDateTime();
          if (dayDate != null) {
            final dayOnly = DateTime(dayDate.year, dayDate.month, dayDate.day);
            if (!dayOnly.isAtSameMomentAs(todayOnly) && !dayOnly.isAtSameMomentAs(tomorrowOnly)) {
              V2AppSnackBar.blocked(context,
                  'Zbog optimizacije kapaciteta, rezervacije za dnevne putnike su moguće samo za tekući dan i sutrašnji dan. Hvala na razumevanju! 🚌');
              return;
            }
          }
        }

        await _showTimePickerDialog(context);
      },
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: (isObrada || isOtkazano) ? 2 : 1,
          ),
        ),
        child: Center(
          child: (hasTime || isObrada || isOdbijeno || isOtkazano || isOdobreno)
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isOtkazano) ...[
                      Icon(Icons.close, size: 14, color: textColor),
                      const SizedBox(width: 2),
                    ] else if (isOdbijeno) ...[
                      Icon(Icons.error_outline, size: 14, color: textColor),
                      const SizedBox(width: 2),
                    ] else if (isObrada) ...[
                      Icon(Icons.hourglass_empty, size: 14, color: textColor),
                      const SizedBox(width: 2),
                    ] else if (isOdobreno) ...[
                      Icon(Icons.check_circle, size: 12, color: textColor),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasTime)
                            Text(
                              value!.split(':').take(2).join(':'),
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: (isObrada || locked || isOtkazano) ? 12 : 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              : Icon(
                  Icons.access_time,
                  color: textColor,
                  size: 18,
                ),
        ),
      ),
    );
  }

  Future<void> _showTimePickerDialog(BuildContext context) async {
    final timePassed = _isTimePassed();

    final navType = navBarTypeNotifier.value;
    List<String> vremena;

    String sezona;
    if (navType == 'praznici') {
      sezona = 'praznici';
    } else if (navType == 'zimski') {
      sezona = 'zimski';
    } else {
      sezona = 'letnji';
    }

    final gradCode = isBC ? 'BC' : 'VS';
    vremena = V2RouteConfig.getVremenaPolazaka(grad: gradCode, sezona: sezona);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
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
                // VREME PROŠLO INFO BANER
                if (timePassed)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: const Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_clock, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'VREME JE PROŠLO',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Možete samo da otkažete termin, izmena nije moguća.',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                // Title
                Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: timePassed ? 12 : 16,
                    bottom: 16,
                  ),
                  child: Text(
                    isBC ? 'BC polazak' : 'VS polazak',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Content
                SizedBox(
                  height: 350,
                  child: ListView(
                    children: [
                      ListTile(
                        title: Text(
                          'Otkaži',
                          style: TextStyle(color: Colors.red.shade300),
                        ),
                        leading: Icon(
                          value == null || value!.isEmpty ? Icons.check_circle : Icons.circle_outlined,
                          color: value == null || value!.isEmpty ? Colors.green : Colors.red.shade300,
                        ),
                        onTap: () async {
                          if (value != null && value!.isNotEmpty) {
                            Navigator.of(dialogContext).pop();
                            onChanged(null);
                          } else {
                            V2AppSnackBar.info(context, 'Vreme polaska je već prazno.');
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          }
                        },
                      ),
                      const Divider(color: Colors.white24),
                      // Time options
                      ...vremena.map((vreme) {
                        final isSelected = value == vreme;
                        final isTimePassedIndividual = _isSpecificTimePassed(vreme);
                        final isDisabled = isTimePassedIndividual;

                        return ListTile(
                          enabled: !isDisabled,
                          title: Text(
                            vreme,
                            style: TextStyle(
                              color: isDisabled ? Colors.white38 : (isSelected ? Colors.white : Colors.white70),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              decoration: isDisabled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          leading: Icon(
                            isDisabled ? Icons.lock_clock : (isSelected ? Icons.check_circle : Icons.circle_outlined),
                            color: isDisabled ? Colors.white38 : (isSelected ? Colors.green : Colors.white54),
                          ),
                          subtitle: isDisabled
                              ? const Text(
                                  '⏰ Vreme je prošlo',
                                  style: TextStyle(color: Colors.red, fontSize: 11),
                                )
                              : null,
                          onTap: isDisabled
                              ? null
                              : () {
                                  onChanged(vreme);
                                  Navigator.of(dialogContext).pop();
                                },
                        );
                      }),
                    ],
                  ),
                ),
                // Actions
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Zatvori', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
