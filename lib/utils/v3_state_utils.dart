import 'package:flutter/material.dart';

/// V3 State Management Utilities
/// Centralizes common state management patterns across V3 screens/widgets
///
/// KORISTI: Eliminiše dupliciranje if(mounted) setState() poziva i loading state pattern-a
/// SIGURNOST: Automatski checked mounted status prije setState poziva
class V3StateUtils {
  /// Safely execute setState with mounted check - PROSTO PROSLIJEDI CALLBACK
  ///
  /// **Koristi umjesto:** if (mounted) setState(() => ...);
  /// **Primjer:** V3StateUtils.safeSetState(this, () => _isLoading = true);
  static void safeSetState(State state, VoidCallback fn) {
    if (state.mounted) {
      (state as dynamic).setState(fn);
    }
  }

  /// Set loading state safely
  ///
  /// **Koristi umjesto:** if (mounted) setState(() => _isLoading = loading);
  /// **Primjer:** V3StateUtils.setLoading(this, true, () => _isLoading = value);
  static void setLoading(State state, bool value, VoidCallback setter) {
    if (state.mounted) {
      (state as dynamic).setState(setter);
    }
  }

  /// Execute async operation with automatic loading state
  ///
  /// **Koristi umjesto:** ručnog loading state management-a
  /// **Primjer:** await V3StateUtils.withLoading(this, () => _setLoading(true), () => _setLoading(false), () async { ... });
  static Future<T> withLoading<T>(
    State state,
    VoidCallback setLoadingTrue,
    VoidCallback setLoadingFalse,
    Future<T> Function() operation,
  ) async {
    if (state.mounted) setLoadingTrue();
    try {
      return await operation();
    } finally {
      if (state.mounted) setLoadingFalse();
    }
  }

  /// Clear error message safely
  ///
  /// **Koristi umjesto:** if (mounted) setState(() => _errorMessage = null);
  /// **Primjer:** V3StateUtils.clearError(this, () => _errorMessage = null);
  static void clearError(State state, VoidCallback clearCallback) {
    if (state.mounted) {
      (state as dynamic).setState(clearCallback);
    }
  }

  /// Set error message safely
  ///
  /// **Koristi umjesto:** if (mounted) setState(() => _errorMessage = message);
  /// **Primjer:** V3StateUtils.setError(this, () => _errorMessage = 'Error');
  static void setError(State state, VoidCallback setErrorCallback) {
    if (state.mounted) {
      (state as dynamic).setState(setErrorCallback);
    }
  }

  /// Batch multiple state updates with mounted check
  ///
  /// **Koristi umjesto:** više if(mounted) setState poziva
  /// **Primjer:** V3StateUtils.batchUpdate(this, () { _loading = false; _error = null; });
  static void batchUpdate(State state, VoidCallback updates) {
    if (state.mounted) {
      (state as dynamic).setState(updates);
    }
  }

  /// Conditional state update
  ///
  /// **Koristi umjesto:** if (condition && mounted) setState(...)
  /// **Primjer:** V3StateUtils.updateIf(this, shouldUpdate, () => _value = newValue);
  static void updateIf(State state, bool condition, VoidCallback update) {
    if (condition && state.mounted) {
      (state as dynamic).setState(update);
    }
  }
}
