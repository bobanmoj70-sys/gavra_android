import 'package:flutter/material.dart';

import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_sms_auth_request_service.dart';
import '../theme.dart';
import '../utils/v3_app_snack_bar.dart';
import '../utils/v3_container_utils.dart';
import '../utils/v3_telefon_helper.dart';

class V3SmsSifreScreen extends StatefulWidget {
  const V3SmsSifreScreen({super.key});

  @override
  State<V3SmsSifreScreen> createState() => _V3SmsSifreScreenState();
}

class _V3SmsSifreScreenState extends State<V3SmsSifreScreen> {
  Future<void> _odobriSmsZahtev(Map<String, dynamic> row) async {
    final broj = ((row['telefon'] ?? '').toString().trim().isNotEmpty)
        ? (row['telefon'] ?? '').toString().trim()
        : (row['telefon_2'] ?? '').toString().trim();
    final sifra = (row['sifra'] ?? '').toString().trim();

    if (broj.isEmpty || sifra.isEmpty) {
      if (!mounted) return;
      V3AppSnackBar.error(context, '❌ Nedostaje broj ili šifra za SMS.');
      return;
    }

    await V3TelefonHelper.otvoriSms(
      context: context,
      state: this,
      broj: broj,
      poruka: 'Vaš verifikacioni kod je: $sifra',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('SMS šifre'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: V3ContainerUtils.backgroundContainer(
        gradient: Theme.of(context).backgroundGradient,
        child: SafeArea(
          child: StreamBuilder<int>(
            stream: V3MasterRealtimeManager.instance.tableRevisionStream('v3_auth'),
            builder: (context, _) {
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: V3SmsAuthRequestService.fetchPendingSmsRequests(limit: 50),
                builder: (context, snapshot) {
                  final pending = snapshot.data ?? const <Map<String, dynamic>>[];

                  if (pending.isEmpty) {
                    return const Center(
                      child: Text(
                        'Nema aktivnih zahteva za šifre.',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: pending.length,
                    itemBuilder: (context, index) {
                      final row = pending[index];
                      final ime = (row['ime'] ?? 'Nepoznat').toString().trim();
                      final broj = ((row['telefon'] ?? '').toString().trim().isNotEmpty)
                          ? (row['telefon'] ?? '').toString().trim()
                          : (row['telefon_2'] ?? '').toString().trim();
                      final sifra = (row['sifra'] ?? '').toString().trim();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ime,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$broj • šifra: $sifra',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 34,
                              child: ElevatedButton.icon(
                                onPressed: () => _odobriSmsZahtev(row),
                                icon: const Icon(Icons.sms, size: 15),
                                label: const Text('Odobri', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
