import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../globals.dart';

enum V3RealtimeConnectionState {
  idle,
  connecting,
  subscribed,
  reconnecting,
  closed,
  error,
}

typedef V3ConnectionStateCallback = void Function(V3RealtimeConnectionState state, {Object? error});

class V3RealtimeConnectionManager {
  V3RealtimeConnectionManager({
    SupabaseClient? client,
    String channelName = 'v3_realtime_all',
  })  : _client = client ?? supabase,
        _channelName = channelName;

  final SupabaseClient _client;
  final String _channelName;

  RealtimeChannel? _channel;
  int _reconnectAttempts = 0;
  bool _disposed = false;
  bool _isSubscribing = false;

  V3RealtimeConnectionState _state = V3RealtimeConnectionState.idle;
  V3RealtimeConnectionState get state => _state;

  Future<RealtimeChannel> connect({
    required void Function(RealtimeChannel channel) configure,
    required V3ConnectionStateCallback onState,
  }) async {
    _setState(V3RealtimeConnectionState.connecting, onState: onState);

    final existingChannel = _channel;
    _channel = null;
    if (existingChannel != null) {
      await _safeRemoveChannel(existingChannel);
    }

    final channel = _client.channel(_channelName);
    configure(channel);

    _channel = channel;
    _isSubscribing = true;

    channel.subscribe((status, [error]) {
      _isSubscribing = false;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _reconnectAttempts = 0;
          _setState(V3RealtimeConnectionState.subscribed, onState: onState);
          break;
        case RealtimeSubscribeStatus.channelError:
          _setState(V3RealtimeConnectionState.error, onState: onState, error: error);
          unawaited(_scheduleReconnect(configure: configure, onState: onState));
          break;
        case RealtimeSubscribeStatus.timedOut:
          _setState(V3RealtimeConnectionState.reconnecting, onState: onState);
          unawaited(_scheduleReconnect(configure: configure, onState: onState));
          break;
        case RealtimeSubscribeStatus.closed:
          _setState(V3RealtimeConnectionState.closed, onState: onState);
          break;
      }
    });

    return channel;
  }

  Future<void> _scheduleReconnect({
    required void Function(RealtimeChannel channel) configure,
    required V3ConnectionStateCallback onState,
  }) async {
    if (_disposed || _isSubscribing) return;

    _reconnectAttempts += 1;
    final delay = _backoffDelay(_reconnectAttempts);
    await Future<void>.delayed(delay);

    if (_disposed) return;
    try {
      await connect(configure: configure, onState: onState);
    } catch (e) {
      _setState(V3RealtimeConnectionState.error, onState: onState, error: e);
    }
  }

  Duration _backoffDelay(int attempt) {
    final cappedAttempt = attempt > 6 ? 6 : attempt;
    final baseMs = 500 * (1 << cappedAttempt);
    final jitter = Random().nextInt(250);
    return Duration(milliseconds: baseMs + jitter);
  }

  Future<void> dispose() async {
    _disposed = true;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _safeRemoveChannel(channel);
    }
  }

  Future<void> _safeRemoveChannel(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (e) {
      debugPrint('[V3RealtimeConnectionManager] removeChannel warning: $e');
    }
  }

  void _setState(
    V3RealtimeConnectionState state, {
    required V3ConnectionStateCallback onState,
    Object? error,
  }) {
    _state = state;
    onState(state, error: error);
  }
}
