import 'dart:async';

class V3EventBus {
  final StreamController<void> _changeController = StreamController<void>.broadcast();
  final StreamController<Set<String>> _tableChangeController = StreamController<Set<String>>.broadcast();
  final StreamController<Map<String, int>> _revisionController = StreamController<Map<String, int>>.broadcast();

  static const Duration defaultDebounceWindow = Duration(milliseconds: 90);
  final Duration emitDebounceWindow;

  final Set<String> _pendingTableChanges = <String>{};
  Timer? _emitDebounceTimer;
  Map<String, int> _lastRevisions = <String, int>{};

  V3EventBus({this.emitDebounceWindow = defaultDebounceWindow});

  Stream<void> get onChange => _changeController.stream;
  Stream<Set<String>> get onTableChange => _tableChangeController.stream;
  Stream<Map<String, int>> get onRevisions => _revisionController.stream;

  Stream<T> streamFromCache<T>({
    required List<String> tables,
    required T Function() build,
  }) {
    final watchedTables = tables.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();

    return _tableChangeController.stream
        .where((changedTables) {
          if (changedTables.contains('*') || watchedTables.isEmpty) return true;
          for (final table in watchedTables) {
            if (changedTables.contains(table)) return true;
          }
          return false;
        })
        .map((_) => build())
        .asBroadcastStream(
          onListen: (subs) => _tableChangeController.add(<String>{'*'}),
        );
  }

  void scheduleEmit({
    Set<String>? tables,
    bool immediate = false,
    Map<String, int>? revisions,
  }) {
    if (tables != null && tables.isNotEmpty) {
      if (tables.contains('*')) {
        _pendingTableChanges
          ..clear()
          ..add('*');
      } else if (!_pendingTableChanges.contains('*')) {
        _pendingTableChanges.addAll(tables);
      }
    }

    if (revisions != null) {
      _lastRevisions = Map<String, int>.from(revisions);
    }

    if (immediate) {
      _emitDebounceTimer?.cancel();
      _emitDebounceTimer = null;
      _flushEmit();
      return;
    }

    final timer = _emitDebounceTimer;
    if (timer != null && timer.isActive) return;
    _emitDebounceTimer = Timer(emitDebounceWindow, _flushEmit);
  }

  void _flushEmit() {
    _emitDebounceTimer = null;

    if (_pendingTableChanges.isEmpty) return;
    final changed = _pendingTableChanges.contains('*') ? <String>{'*'} : Set<String>.from(_pendingTableChanges);
    _pendingTableChanges.clear();

    _changeController.add(null);
    _tableChangeController.add(changed);
    _revisionController.add(Map<String, int>.from(_lastRevisions));
  }

  Future<void> dispose() async {
    _emitDebounceTimer?.cancel();
    await _changeController.close();
    await _tableChangeController.close();
    await _revisionController.close();
  }
}
