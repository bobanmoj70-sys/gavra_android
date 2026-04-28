import 'dart:async';

class V3EventBus {
  final StreamController<Map<String, int>> _revisionController =
      StreamController<Map<String, int>>.broadcast();

  static const Duration defaultDebounceWindow = Duration(milliseconds: 90);
  final Duration emitDebounceWindow;

  final Set<String> _pendingTableChanges = <String>{};
  Timer? _emitDebounceTimer;
  Map<String, int> _lastRevisions = <String, int>{};

  V3EventBus({this.emitDebounceWindow = defaultDebounceWindow});

  Stream<Map<String, int>> get onRevisions => _revisionController.stream;

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
    final changed = _pendingTableChanges.contains('*')
        ? <String>{'*'}
        : Set<String>.from(_pendingTableChanges);
    _pendingTableChanges.clear();

    _revisionController.add(Map<String, int>.from(_lastRevisions));
  }

  Future<void> dispose() async {
    _emitDebounceTimer?.cancel();
    await _revisionController.close();
  }
}
