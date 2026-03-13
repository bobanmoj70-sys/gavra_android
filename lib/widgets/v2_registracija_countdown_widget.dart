import 'package:flutter/material.dart';

import '../screens/v3_odrzavanje_screen.dart';
import '../services/v2_vozila_service.dart';

/// Helper klasa za deljene podatke o registraciji
class _RegistracijaData {
  static V2Vozilo? najblizeVozilo;
  static int? danaDoIsteka;
  static bool isLoading = true;
  static bool _isLoadingInProgress = false; // Race condition guard
  static final List<VoidCallback> _listeners = [];

  static void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }

  static void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }

  static void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  static Future<void> load() async {
    if (_isLoadingInProgress) return; // Sprecava paralelne pozive
    _isLoadingInProgress = true;
    try {
      final vozila = V2VozilaService.getVozila();
      final now = DateTime.now(); // Jednom pre petlje

      V2Vozilo? najblize;
      int? minDana;

      for (final v in vozila) {
        if (v.registracijaVaziDo != null) {
          final dana = v.registracijaVaziDo!.difference(now).inDays;
          if (minDana == null || dana < minDana) {
            minDana = dana;
            najblize = v;
          }
        }
      }

      najblizeVozilo = najblize;
      danaDoIsteka = minDana;
      isLoading = false;
      _notifyListeners();
    } catch (e, st) {
      debugPrint('[_RegistracijaData.load] Greška: $e\n$st');
      isLoading = false;
      _notifyListeners();
    } finally {
      _isLoadingInProgress = false;
    }
  }

  /// Treba sakriti widget (nema podataka ili vise od 14 dana do isteka)
  static bool get shouldHide => isLoading || najblizeVozilo == null || (danaDoIsteka != null && danaDoIsteka! > 14);

  /// Otvori kolsku knjigu i ponovo ucitaj podatke posle zatvaranja
  static void openKolskaKnjiga(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const V3OdrzavanjeScreen()),
    ).then((_) => load());
  }

  // Slika tablice za vozilo
  static String getTablicaImage(String registarskiBroj) {
    if (registarskiBroj.contains('066')) return 'assets/tablica_066.png';
    if (registarskiBroj.contains('088')) return 'assets/tablica_088.png';
    if (registarskiBroj.contains('093')) return 'assets/tablica_093.png';
    if (registarskiBroj.contains('097')) return 'assets/tablica_097.png';
    if (registarskiBroj.contains('102')) return 'assets/tablica_102.png';
    return 'assets/tablica_066.png';
  }

  // Boja teksta za dane - nijanse od 14 do 0
  static Color getDanaColor() {
    if (danaDoIsteka == null) return Colors.grey;
    if (danaDoIsteka! < 0) return Colors.red.shade900; // Istekla - tamno crvena
    if (danaDoIsteka! <= 2) return Colors.red; // 0-2 dana - crvena
    if (danaDoIsteka! <= 5) {
      return Colors.deepOrange; // 3-5 dana - tamno narandžasta
    }
    if (danaDoIsteka! <= 8) return Colors.orange; // 6-8 dana - narandžasta
    if (danaDoIsteka! <= 11) return Colors.amber; // 9-11 dana - žuta
    return Colors.lime; // 12-14 dana - limeta
  }
}

/// Tablica widget - samo slika tablice (leva strana)
class V2RegistracijaTablicaWidget extends StatefulWidget {
  const V2RegistracijaTablicaWidget({super.key});

  @override
  State<V2RegistracijaTablicaWidget> createState() => _RegistracijaTablicaWidgetState();
}

class _RegistracijaTablicaWidgetState extends State<V2RegistracijaTablicaWidget> {
  @override
  void initState() {
    super.initState();
    _RegistracijaData.addListener(_onDataChanged);
    if (_RegistracijaData.isLoading) {
      _RegistracijaData.load();
    }
  }

  @override
  void dispose() {
    _RegistracijaData.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_RegistracijaData.shouldHide) return const SizedBox.shrink();

    final tablicaImage = _RegistracijaData.getTablicaImage(
      _RegistracijaData.najblizeVozilo!.registarskiBroj,
    );

    return GestureDetector(
      onTap: () => _RegistracijaData.openKolskaKnjiga(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Image.asset(
          tablicaImage,
          width: 75,
          height: 19,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

/// Brojac widget - samo broj dana (desna strana)
class V2RegistracijaBrojacWidget extends StatefulWidget {
  const V2RegistracijaBrojacWidget({super.key});

  @override
  State<V2RegistracijaBrojacWidget> createState() => _RegistracijaBrojacWidgetState();
}

class _RegistracijaBrojacWidgetState extends State<V2RegistracijaBrojacWidget> {
  @override
  void initState() {
    super.initState();
    _RegistracijaData.addListener(_onDataChanged);
    if (_RegistracijaData.isLoading) {
      _RegistracijaData.load();
    }
  }

  @override
  void dispose() {
    _RegistracijaData.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_RegistracijaData.shouldHide) return const SizedBox.shrink();

    final danaDoIsteka = _RegistracijaData.danaDoIsteka!;
    final danaText = danaDoIsteka < 0 ? '-${danaDoIsteka.abs()}d' : '${danaDoIsteka}d';

    return GestureDetector(
      onTap: () => _RegistracijaData.openKolskaKnjiga(context),
      child: Text(
        danaText,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: _RegistracijaData.getDanaColor(),
          shadows: const [
            Shadow(
              blurRadius: 4,
              color: Colors.black54,
            ),
          ],
        ),
      ),
    );
  }
}
