import 'package:flutter/material.dart';
import 'package:gavra_android/models/v3_zahtev.dart';
import 'package:gavra_android/models/v3_putnik.dart';
import 'package:gavra_android/services/v3/v3_zahtev_service.dart';
import 'package:gavra_android/services/v3/v3_putnik_service.dart';
import 'package:gavra_android/services/realtime/v3_master_realtime_manager.dart';
import 'package:gavra_android/utils/v2_app_snack_bar.dart';

class V2PolasciScreen extends StatefulWidget {
  const V2PolasciScreen({super.key});

  @override
  State<V2PolasciScreen> createState() => _V2PolasciScreenState();
}

class _V2PolasciScreenState extends State<V2PolasciScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📋 Zahtevi Rezervacija (V3)')),
      body: StreamBuilder<void>(
        stream: V3MasterRealtimeManager.instance.onChange,
        builder: (context, snapshot) {
          final allZahtevi = V3MasterRealtimeManager.instance.zahteviCache.values
              .map((v) => V3Zahtev.fromJson(v))
              .where((z) => z.status == 'obrada' && z.aktivno)
              .toList()
            ..sort((a, b) => a.zeljenoVreme.compareTo(b.zeljenoVreme));

          if (allZahtevi.isEmpty) {
            return const Center(child: Text('Nema aktivnih zahteva na čekanju.'));
          }

          return ListView.builder(
            itemCount: allZahtevi.length,
            itemBuilder: (context, i) {
              final z = allZahtevi[i];
              final p = V3PutnikService.getPutnikById(z.putnikId);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(p?.imePrezime ?? 'Nepoznat putnik'),
                  subtitle: Text('${z.grad} | ${z.zeljenoVreme} | ${z.danUSedmici ?? ""}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _updateStatus(z.id, 'odobreno'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _updateStatus(z.id, 'odbijeno'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await V3ZahtevService.updateStatus(id, status);
      if (mounted) V2AppSnackBar.success(context, '✅ Zahtev: $status');
    } catch (e) {
      if (mounted) V2AppSnackBar.error(context, '❌ Greška: $e');
    }
  }
}
