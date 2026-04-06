import 'dart:async';

/// V3StreamUtils - ЦЕНТРАЛИЗОВАНО УПРАВЉАЊЕ STREAM-ОВИМА И TIMER-ОВИМА
/// Елиминише све StreamSubscription и Timer дупликате!
class V3StreamUtils {
  // Мапе за чување активних subscription-а и timer-а
  static final Map<String, StreamSubscription<dynamic>> _subscriptions = {};
  static final Map<String, Timer> _timers = {};

  // ─── STREAMSUBSCRIPTION УПРАВЉАЊЕ ──────────────────────────────────

  /// Креира нови StreamSubscription са кључем
  static StreamSubscription<T> subscribe<T>({
    required String key,
    required Stream<T> stream,
    required void Function(T) onData,
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    // Cancel existing subscription if exists
    cancelSubscription(key);

    late final StreamSubscription<T> subscription;
    subscription = stream.listen(
      onData,
      onError: onError,
      onDone: () {
        if (identical(_subscriptions[key], subscription)) {
          _subscriptions.remove(key);
        }
        onDone?.call();
      },
      cancelOnError: cancelOnError,
    );

    _subscriptions[key] = subscription;
    return subscription;
  }

  /// Добиј постојећи subscription
  static StreamSubscription<dynamic>? getSubscription(String key) {
    return _subscriptions[key];
  }

  /// Async cancel subscription по кључу
  static Future<void> cancelSubscriptionAsync(String key) async {
    final subscription = _subscriptions.remove(key);
    if (subscription != null) {
      await subscription.cancel();
    }
  }

  /// Cancel subscription по кључу
  static void cancelSubscription(String key) {
    unawaited(cancelSubscriptionAsync(key));
  }

  /// Async cancel све subscription-е
  static Future<void> cancelAllSubscriptionsAsync() async {
    final subscriptions = _subscriptions.values.toList(growable: false);
    _subscriptions.clear();
    await Future.wait(subscriptions.map((sub) => sub.cancel()));
  }

  /// Cancel све subscription-е
  static void cancelAllSubscriptions() {
    unawaited(cancelAllSubscriptionsAsync());
  }

  /// Провери да ли је subscription активан
  static bool isSubscriptionActive(String key) {
    return _subscriptions.containsKey(key);
  }

  // ─── TIMER УПРАВЉАЊЕ ───────────────────────────────────────────────

  /// Креира Timer.periodic са кључем
  static Timer createPeriodicTimer({
    required String key,
    required Duration period,
    required void Function(Timer) callback,
  }) {
    // Cancel existing timer if exists
    cancelTimer(key);

    final timer = Timer.periodic(period, callback);
    _timers[key] = timer;
    return timer;
  }

  /// Креира једнократни Timer са кључем
  static Timer createTimer({
    required String key,
    required Duration duration,
    required void Function() callback,
  }) {
    // Cancel existing timer if exists
    cancelTimer(key);

    final timer = Timer(duration, () {
      _timers.remove(key);
      callback();
    });
    _timers[key] = timer;
    return timer;
  }

  /// Добиј постојећи timer
  static Timer? getTimer(String key) {
    return _timers[key];
  }

  /// Cancel timer по кључу
  static void cancelTimer(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
  }

  /// Cancel све timer-е
  static void cancelAllTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Провери да ли је timer активан
  static bool isTimerActive(String key) {
    final timer = _timers[key];
    return timer != null && timer.isActive;
  }

  // ─── СПЕЦИЈАЛИЗОВАНЕ МЕТОДЕ ─────────────────────────────────────────

  /// Cache subscription за realtime updates
  static StreamSubscription<void> subscribeToCacheUpdates({
    required String key,
    required Stream<void> cacheStream,
    required void Function() onUpdate,
  }) {
    return subscribe<void>(
      key: '${key}_cache',
      stream: cacheStream,
      onData: (_) => onUpdate(),
    );
  }

  /// GPS position subscription
  static StreamSubscription<T> subscribeToGPS<T>({
    required String key,
    required Stream<T> positionStream,
    required void Function(T) onPosition,
    void Function(Object)? onError,
  }) {
    return subscribe<T>(
      key: '${key}_gps',
      stream: positionStream,
      onData: onPosition,
      onError: onError,
    );
  }

  /// Zahtev subscription
  static StreamSubscription<List<Map<String, dynamic>>> subscribeToPinRequests({
    required String key,
    required Stream<List<Map<String, dynamic>>> pinStream,
    required void Function(List<Map<String, dynamic>>) onPinUpdate,
  }) {
    return subscribe<List<Map<String, dynamic>>>(
      key: '${key}_pin',
      stream: pinStream,
      onData: onPinUpdate,
    );
  }

  /// Refresh timer за периодичне операције
  static Timer createRefreshTimer({
    required String key,
    Duration period = const Duration(seconds: 30),
    required void Function() onRefresh,
  }) {
    return createPeriodicTimer(
      key: '${key}_refresh',
      period: period,
      callback: (_) => onRefresh(),
    );
  }

  /// Route optimization timer
  static Timer createRouteOptimizationTimer({
    required String key,
    Duration period = const Duration(minutes: 2),
    required void Function() onOptimize,
  }) {
    return createPeriodicTimer(
      key: '${key}_route_opt',
      period: period,
      callback: (_) => onOptimize(),
    );
  }

  /// Long press timer за UI
  static Timer createLongPressTimer({
    required String key,
    Duration duration = const Duration(milliseconds: 500),
    required void Function() onLongPress,
  }) {
    return createTimer(
      key: '${key}_longpress',
      duration: duration,
      callback: onLongPress,
    );
  }

  /// Debounce timer за спречавање честих позива
  static Timer createDebounceTimer({
    required String key,
    Duration duration = const Duration(milliseconds: 300),
    required void Function() callback,
  }) {
    return createTimer(
      key: '${key}_debounce',
      duration: duration,
      callback: callback,
    );
  }

  // ─── МАСОВНЕ ОПЕРАЦИЈЕ ──────────────────────────────────────────────

  /// Cancel све по префиксу кључа
  static void cancelByPrefix(String prefix) {
    // Cancel subscriptions
    final subKeysToRemove = <String>[];
    for (final key in _subscriptions.keys) {
      if (key.startsWith(prefix)) {
        _subscriptions[key]?.cancel();
        subKeysToRemove.add(key);
      }
    }
    for (final key in subKeysToRemove) {
      _subscriptions.remove(key);
    }

    // Cancel timers
    final timerKeysToRemove = <String>[];
    for (final key in _timers.keys) {
      if (key.startsWith(prefix)) {
        _timers[key]?.cancel();
        timerKeysToRemove.add(key);
      }
    }
    for (final key in timerKeysToRemove) {
      _timers.remove(key);
    }
  }

  /// Async cancel све по префиксу кључа (за subscription-е)
  static Future<void> cancelByPrefixAsync(String prefix) async {
    final subKeys = _subscriptions.keys.where((key) => key.startsWith(prefix)).toList(growable: false);
    final subscriptions = subKeys
        .map((key) => _subscriptions.remove(key))
        .whereType<StreamSubscription<dynamic>>()
        .toList(growable: false);

    await Future.wait(subscriptions.map((sub) => sub.cancel()));

    final timerKeys = _timers.keys.where((key) => key.startsWith(prefix)).toList(growable: false);
    for (final key in timerKeys) {
      _timers.remove(key)?.cancel();
    }
  }

  /// ТОТАЛНО УНИШТАВАЊЕ свих stream-ова и timer-а
  static void disposeAll() {
    cancelAllSubscriptions();
    cancelAllTimers();
  }

  /// Async varijanta totalnog čišćenja
  static Future<void> disposeAllAsync() async {
    await cancelAllSubscriptionsAsync();
    cancelAllTimers();
  }

  /// Добиј статистике
  static Map<String, int> getStats() {
    return {
      'activeSubscriptions': _subscriptions.length,
      'activeTimers': _timers.values.where((t) => t.isActive).length,
      'totalTimers': _timers.length,
    };
  }
}
