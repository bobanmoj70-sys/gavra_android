import 'dart:async';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../models/v3_uplata_pazara.dart';
import '../screens/v3_vozac_pazar_popup.dart';
import '../services/realtime/v3_master_realtime_manager.dart';
import '../services/v3/v3_uplata_pazara_service.dart';
import '../services/v3/v3_vozac_service.dart';

class V3PazarListener extends StatefulWidget {
  final Widget child;

  const V3PazarListener({super.key, required this.child});

  @override
  State<V3PazarListener> createState() => _V3PazarListenerState();
}

class _V3PazarListenerState extends State<V3PazarListener> {
  StreamSubscription<int>? _revisionSub;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[V3PazarListener] initState - listener aktiviran (realtime)');

    // Jednokratna provera pri pokretanju (fallback ako cache nije spreman)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPazar(fromRealtime: false));

    // Slušamo promene u tabeli v3_uplata_pazara preko realtime manager-a
    _revisionSub = V3MasterRealtimeManager.instance.tableRevisionStream('v3_uplata_pazara').listen((revision) {
      debugPrint('[V3PazarListener] realtime promena u v3_uplata_pazara (revision=$revision)');
      _checkPazar(fromRealtime: true);
    });
  }

  @override
  void dispose() {
    _revisionSub?.cancel();
    super.dispose();
  }

  Future<void> _checkPazar({required bool fromRealtime}) async {
    if (_dialogOpen) {
      debugPrint('[V3PazarListener] dialog je već otvoren, preskačem');
      return;
    }

    final vozacId = V3VozacService.currentVozac?.id;
    if (vozacId == null || vozacId.isEmpty) {
      debugPrint('[V3PazarListener] currentVozac je null/empty');
      return;
    }

    final today = DateTime.now();
    debugPrint('[V3PazarListener] proveravam vozacId=$vozacId za ${today.day}.${today.month}.${today.year}');

    final cacheMap = V3MasterRealtimeManager.instance.uplataPazaraCache;
    debugPrint('[V3PazarListener] cache veličina=${cacheMap.length}');

    Map<String, dynamic>? targetRow;
    for (final row in cacheMap.values) {
      if (row['vozac_id'] == vozacId && row['mesec'] == today.month && row['godina'] == today.year) {
        targetRow = row;
        break;
      }
    }

    // Ako nema u cache-u i ovo nije realtime event, proveri bazu kao fallback
    if (targetRow == null && !fromRealtime) {
      debugPrint('[V3PazarListener] nema u cache-u, proveravam bazu...');
      try {
        final uplata = await V3UplataPazaraService.getZaVozacaIMesec(
          vozacId: vozacId,
          datum: today,
        );
        if (uplata != null) {
          targetRow = uplata.toJson();
          debugPrint('[V3PazarListener] pronađeno u bazi');
        } else {
          debugPrint('[V3PazarListener] nema zapisa u bazi');
        }
      } catch (e) {
        debugPrint('[V3PazarListener] greška pri čitanju baze: $e');
      }
    } else if (targetRow != null) {
      debugPrint('[V3PazarListener] pronađeno u cache-u');
    }

    if (targetRow == null) return;

    final uplata = V3UplataPazara.fromJson(targetRow);
    final dnevna = uplata.uplataZaDan(today.day);

    if (dnevna == null) {
      debugPrint('[V3PazarListener] nema dnevne uplate za dan ${today.day}');
      return;
    }

    debugPrint('[V3PazarListener] dnevna uplata: predao=${dnevna.predao}, zahtevanUnos=${dnevna.zahtevanUnos}');

    if (dnevna.zahtevanUnos == true) {
      debugPrint('[V3PazarListener] POKREĆEM popup!');
      _dialogOpen = true;

      final navContext = navigatorKey.currentContext;
      if (navContext == null) {
        debugPrint('[V3PazarListener] navigatorKey.currentContext je null, ne mogu otvoriti popup');
        _dialogOpen = false;
        return;
      }

      await showDialog(
        context: navContext,
        barrierDismissible: false,
        builder: (_) => V3VozacPazarPopup(
          datum: today,
          ukupno: dnevna.ukupno,
          onSaved: () {
            navigatorKey.currentState?.pop();
          },
        ),
      );
      _dialogOpen = false;
      debugPrint('[V3PazarListener] popup zatvoren');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
