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
}
