import 'package:flutter/material.dart';

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
