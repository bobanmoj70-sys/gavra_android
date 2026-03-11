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
