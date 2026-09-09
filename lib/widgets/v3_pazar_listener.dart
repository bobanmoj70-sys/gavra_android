import 'dart:async';

import 'package:flutter/material.dart';

import '../globals.dart';
import '../screens/v3_vozac_pazar_popup.dart';
import '../services/realtime/v3_master_realtime_manager.dart';

class V3PazarListener extends StatefulWidget {
  final Widget child;

  const V3PazarListener({super.key, required this.child});

  @override
  State<V3PazarListener> createState() => _V3PazarListenerState();
}

class _V3PazarListenerState extends State<V3PazarListener> {
  StreamSubscription<V3PazarPromptEvent>? _promptSub;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[V3PazarListener] initState - UI subscriber aktiviran');

    final manager = V3MasterRealtimeManager.instance;
    manager.startPazarMonitoring();
    _promptSub = manager.pazarPromptStream.listen((event) {
      _showPazarPopup(event);
    });
  }

  @override
  void dispose() {
    _promptSub?.cancel();
    V3MasterRealtimeManager.instance.stopPazarMonitoring();
    super.dispose();
  }

  Future<void> _showPazarPopup(V3PazarPromptEvent event) async {
    if (_dialogOpen) return;

    final navContext = navigatorKey.currentContext;
    if (navContext == null) {
      debugPrint('[V3PazarListener] navigatorKey.currentContext je null, ne mogu otvoriti popup');
      return;
    }

    _dialogOpen = true;
    await showDialog(
      context: navContext,
      barrierDismissible: false,
      builder: (_) => V3VozacPazarPopup(
        datum: event.datum,
        ukupno: event.ukupno,
        naknadnaNaplataDetektovana: event.naknadnaNaplataDetektovana,
        onSaved: () {
          navigatorKey.currentState?.pop();
        },
      ),
    );
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
