import 'dart:async';

import 'package:flutter/material.dart';

class V3LiveClockText extends StatelessWidget {
  final TextStyle? style;
  final TextAlign textAlign;
  final int precisionSeconds;

  const V3LiveClockText({
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.precisionSeconds = 1,
  }) : assert(precisionSeconds > 0);

  String _formatNow() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(Duration(seconds: precisionSeconds), (tick) => tick),
      initialData: 0,
      builder: (context, _) {
        return Text(
          _formatNow(),
          style: style,
          textAlign: textAlign,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
