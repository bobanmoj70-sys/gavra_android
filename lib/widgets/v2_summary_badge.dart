import 'package:flutter/material.dart';

import '../models/v2_polazak.dart';
import '../models/v3_zahtev.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../theme.dart';
import '../utils/v2_app_snack_bar.dart';
import '../utils/v2_vozac_cache.dart';

/// Zajednički badge widget za prikaz statusa u zahtjev-screenima.
/// Koristi se u v2_radnici_zahtevi_screen, v2_ucenici_zahtevi_screen,
/// v2_posiljke_zahtevi_screen umjesto identičnih privatnih kopija.
Widget v2SummaryBadge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );

Widget v2VremeChip(String label, String vreme, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Text('$label: ', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
        Text(vreme, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );

Widget v2TimelineChip(String label, String value, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
        Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );

Widget v2GradBadge(String grad) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(grad, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );

/// Kartica zahtjeva — identična u posiljke/radnici/ucenici zahtjev-screenima.
Widget v2ZahtjevKartica(BuildContext context, V2Polazak z) {
  final ime = z.putnikIme ?? 'Nepoznat';
  final grad = z.grad ?? 'BC';
  final dan = z.dan ?? '';
  final zeljeno = z.zeljenoVreme ?? '—';
  final dodeljeno = z.dodeljenoVreme;
  final alt1 = z.alternativeVreme1;
  final alt2 = z.alternativeVreme2;
  final status = z.status;

  final (statusColor, statusLabel) = switch (status) {
    'obrada' => (Colors.amber, 'OBRADA'),
    'odobreno' => (Colors.green, 'ODOBRENO'),
    'odbijeno' => (Colors.red, 'ODBIJENO'),
    'otkazano' => (Colors.orange, 'OTKAZANO'),
    _ => (Colors.grey, status.toUpperCase()),
  };

  final poslatStr = z.createdAt != null
      ? '${z.createdAt!.toLocal().day.toString().padLeft(2, '0')}.${z.createdAt!.toLocal().month.toString().padLeft(2, '0')}. ${z.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${z.createdAt!.toLocal().minute.toString().padLeft(2, '0')}'
      : null;
  final obradjenoStr = z.processedAt != null
      ? '${z.processedAt!.toLocal().day.toString().padLeft(2, '0')}.${z.processedAt!.toLocal().month.toString().padLeft(2, '0')}. ${z.processedAt!.toLocal().hour.toString().padLeft(2, '0')}:${z.processedAt!.toLocal().minute.toString().padLeft(2, '0')}'
      : null;
  final koObradio = z.approvedBy ?? z.cancelledBy;
  final koObradioColor = V2VozacCache.getColor(koObradio);

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).glassContainer.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(ime,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.calendar_today, size: 12, color: Colors.amber.withValues(alpha: 0.8)),
                    const SizedBox(width: 3),
                    Text(dan, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                  ],
                ),
              ),
              v2GradBadge(grad),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child:
                    Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              v2VremeChip('Željeno', zeljeno, Colors.white70),
              if (dodeljeno != null && dodeljeno.isNotEmpty) v2VremeChip('', '→ $dodeljeno', Colors.green),
              if (alt1 != null && alt1.isNotEmpty) v2VremeChip('Alt 1', alt1, Colors.lightBlue),
              if (alt2 != null && alt2.isNotEmpty) v2VremeChip('Alt 2', alt2, Colors.lightBlue),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              if (poslatStr != null) v2TimelineChip('📨 poslato', poslatStr, Colors.white54),
              if (obradjenoStr != null) v2TimelineChip('⚙️ obrađeno', obradjenoStr, Colors.lightBlueAccent),
              if (obradjenoStr == null && status == 'obrada') v2TimelineChip('⏳', 'čeka kronom', Colors.amber.shade200),
              if (koObradio != null) v2TimelineChip('👤', koObradio, koObradioColor),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Prikazuje error snackbar — identično u svim screen-ima.
/// Zamjenjuje privatni _showError(String) koji je bio kopiran u više screena.
void v2ShowError(BuildContext context, String message) {
  if (context.mounted) {
    V2AppSnackBar.error(context, message);
  }
}

/// Lista zahtjeva sa praznim stanjem — identična u posiljke/radnici/ucenici zahtjev-screenima.
/// Razlika između screena je samo [emptyIcon] i [emptyText].
Widget v2ZahtjevLista(
  BuildContext context,
  List<V2Polazak> zahtevi,
  IconData emptyIcon,
  String emptyText,
) {
  if (zahtevi.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(emptyIcon, size: 72, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(
            emptyText,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    itemCount: zahtevi.length,
    itemBuilder: (_, index) => v2ZahtjevKartica(context, zahtevi[index]),
  );
}

/// Kartica v3 zahtjeva (putnici, pošiljke, radnici, učenici).
Widget v3ZahtjevKartica(BuildContext context, V3Zahtev z) {
  final ime = V3MasterRealtimeManager.instance.putniciCache[z.putnikId]?['ime'] ?? 'Nepoznat';
  final grad = z.grad;
  final dan = z.datum.toIso8601String().split('T')[0]; // Formatiranje datuma
  final zeljeno = z.zeljenoVreme;
  final status = z.status;

  final (statusColor, statusLabel) = switch (status) {
    'obrada' => (Colors.amber, 'OBRADA'),
    'odobreno' => (Colors.green, 'ODOBRENO'),
    'odbijeno' => (Colors.red, 'ODBIJENO'),
    'otkazano' => (Colors.orange, 'OTKAZANO'),
    _ => (Colors.grey, status.toUpperCase()),
  };

  final poslatStr = z.createdAt != null
      ? '${z.createdAt!.toLocal().day.toString().padLeft(2, '0')}.${z.createdAt!.toLocal().month.toString().padLeft(2, '0')}. ${z.createdAt!.toLocal().hour.toString().padLeft(2, '0')}:${z.createdAt!.toLocal().minute.toString().padLeft(2, '0')}'
      : '';

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).glassContainer.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(ime,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.calendar_today, size: 12, color: Colors.amber.withValues(alpha: 0.8)),
                    const SizedBox(width: 3),
                    Text(dan, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                  ],
                ),
              ),
              v2GradBadge(grad),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child:
                    Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              v2VremeChip('Željeno', zeljeno, Colors.white70),
              if (z.brojMesta > 1) v2VremeChip('Mesta', z.brojMesta.toString(), Colors.amber),
            ],
          ),
          if (poslatStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            v2TimelineChip('📨 poslato', poslatStr, Colors.white54),
          ],
          if (z.napomena != null && z.napomena!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(z.napomena!,
                style:
                    TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    ),
  );
}

/// Lista V3 zahtjeva.
Widget v3ZahtjevLista(
  BuildContext context,
  List<V3Zahtev> zahtevi,
  IconData emptyIcon,
  String emptyText,
) {
  if (zahtevi.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(emptyIcon, size: 72, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(
            emptyText,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
  return ListView.builder(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    itemCount: zahtevi.length,
    itemBuilder: (_, index) => v3ZahtjevKartica(context, zahtevi[index]),
  );
}
