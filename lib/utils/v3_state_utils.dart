import 'package:flutter/material.dart';

/// Bezbedan setState sa mounted check-om.
class V3StateUtils {
  /// if (mounted) setState(() => ...)
  static void safeSetState(State state, VoidCallback fn) {
    if (state.mounted) {
      // ignore: invalid_use_of_protected_member
      (state as dynamic).setState(fn);
    }
  }
}
