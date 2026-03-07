import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../globals.dart';
import '../screens/v2_home_screen.dart';
import '../screens/v2_pin_zahtevi_screen.dart';
import '../screens/v2_putnik_profil_screen.dart';
import '../screens/v2_vozac_screen.dart';
import 'realtime/v2_master_realtime_manager.dart';

class V2NotificationNavigationService {
  V2NotificationNavigationService._();

  /// Navigiraj na putnikov profil ekran (za "transport_started" ili seat request notifikacije)
  static Future<void> navigateToPassengerProfile() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final putnikId = prefs.getString('registrovani_putnik_id');

      if (putnikId == null) {
        return;
      }

      // Učitaj podatke putnika iz cache-a
      final response = V2MasterRealtimeManager.instance.v2GetPutnikById(putnikId);
      if (response == null) {
        return;
      }

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => V2PutnikProfilScreen(
              putnikData: response,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[V2NotificationNavigationService] navigateToPassengerProfile greška: $e');
    }
  }

  /// Navigiraj na Vozač Screen (za 'vozac_krenuo' notifikaciju)
  static Future<void> navigateToVozacScreen() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    try {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const V2VozacScreen(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[V2NotificationNavigationService] navigateToVozacScreen greška: $e');
    }
  }

  /// Navigiraj na PIN zahtevi ekran (za admina)
  static Future<void> navigateToPinZahtevi() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    try {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const V2PinZahteviScreen(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[V2NotificationNavigationService] navigateToPinZahtevi greška: $e');
    }
  }

  static Future<void> navigateToPassenger({
    required String type,
    required Map<String, dynamic> putnikData,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    try {
      final putnikIme = putnikData['ime'] ?? '';
      final putnikDan = putnikData['dan'] ?? '';
      final tipPutnika = putnikData['tipPutnika'] as String?;

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  type == 'novi_putnik' ? Icons.person_add : Icons.person_remove,
                  color: type == 'novi_putnik' ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    type == 'novi_putnik' ? 'Novi V2Putnik dodat' : 'V2Putnik otkazan',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '👤 $putnikIme',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (putnikDan is String && putnikDan.isNotEmpty)
                  Text(
                    '📅 Dan: $putnikDan',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (putnikData['polazak'] != null)
                  Text(
                    '🕐 Polazak: ${putnikData['polazak']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (putnikData['grad'] != null)
                  Text(
                    '🏘️ Destinacija: ${putnikData['grad']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                if (tipPutnika != null && tipPutnika.isNotEmpty)
                  Text(
                    '🏷️ Tip: ${tipPutnika[0].toUpperCase()}${tipPutnika.substring(1)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Vreme: ${DateTime.now().toString().substring(0, 19)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Zatvori'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _navigateToAppropriateScreen(context);
                },
                child: const Text('Otvori'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (context.mounted) {
        _showErrorDialog(context, 'Greška pri otvaranju putnika: $e');
      }
    }
  }

  static void _navigateToAppropriateScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const V2HomeScreen(),
      ),
    );
  }

  static void _showErrorDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Greška'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('U redu'),
            ),
          ],
        );
      },
    );
  }
}
