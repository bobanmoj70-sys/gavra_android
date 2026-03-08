import 'dart:async';

import 'package:flutter/material.dart';

/// V2ClockTicker - a lightweight widget that updates once per second and
/// only rebuilds itself (the time text), reducing rebuild impact on
/// surrounding widgets. It pauses updates when the app is in background.
class V2ClockTicker extends StatefulWidget {
  const V2ClockTicker({
    super.key,
    this.style,
    this.showSeconds = true,
  });

  final TextStyle? style;
  final bool showSeconds;

  @override
  State<V2ClockTicker> createState() => _ClockTickerState();
}

class _ClockTickerState extends State<V2ClockTicker> with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _now = DateTime.now();
    // Poravnaj prvi tick na sledecu punu sekundu da bi prikaz bio ujednacen
    final msUntilNextSecond = 1000 - _now.millisecond;
    _timer = Timer(Duration(milliseconds: msUntilNextSecond), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      // Nakon prvog poravnatog tick-a, nastavi sa periodicnim tick-ovima
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _stopTimer();
    } else if (state == AppLifecycleState.resumed) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final display = widget.showSeconds ? '$h:$m:${_now.second.toString().padLeft(2, '0')}' : '$h:$m';

    return Text(
      display,
      style: widget.style,
    );
  }
}
