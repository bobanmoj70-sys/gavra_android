import 'dart:async';

import 'package:flutter/material.dart';

class V3LiveClockText extends StatefulWidget {
  final TextStyle? style;
  final TextAlign textAlign;
  final int precisionSeconds;

  const V3LiveClockText({
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.precisionSeconds = 1,
  }) : assert(precisionSeconds > 0);

  @override
  State<V3LiveClockText> createState() => _V3LiveClockTextState();
}

class _V3LiveClockTextState extends State<V3LiveClockText> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant V3LiveClockText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.precisionSeconds != widget.precisionSeconds) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: widget.precisionSeconds), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  String _formatNow() {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatNow(),
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}
