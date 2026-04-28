class V3CacheStore {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = <String, Map<String, Map<String, dynamic>>>{};
  final Map<String, int> _revisions = <String, int>{};
  final Map<String, DateTime?> _watermarks = <String, DateTime?>{};

  void registerTable(String table, Map<String, Map<String, dynamic>> cache) {
    _tables[table] = cache;
    _revisions.putIfAbsent(table, () => 0);
    _watermarks.putIfAbsent(table, () => null);
  }

  Map<String, Map<String, dynamic>> table(String table) {
    return _tables[table] ?? <String, Map<String, dynamic>>{};
  }

  int revision(String table) => _revisions[table] ?? 0;

  DateTime? watermark(String table) => _watermarks[table];

  Map<String, int> revisionsSnapshot() => Map<String, int>.from(_revisions);

  void replaceAll(String table, List<dynamic> rows) {
    final cache = _tables[table];
    if (cache == null) return;

    cache.clear();
    DateTime? maxTs;

    for (final raw in rows) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id']?.toString();
      if (id == null || id.isEmpty) continue;
      cache[id] = Map<String, dynamic>.from(raw);
      maxTs = _maxTime(maxTs, _extractTimestamp(raw));
    }

    if (maxTs != null) {
      _watermarks[table] = maxTs;
    }

    _touch(table);
  }

  bool applyRealtimeMutation({
    required String table,
    required Map<String, dynamic> newRecord,
    required Map<String, dynamic> oldRecord,
    required bool isDelete,
  }) {
    final cache = _tables[table];
    if (cache == null) return false;

    final id = (newRecord['id'] ?? oldRecord['id'])?.toString();
    if (id == null || id.isEmpty) return false;

    final hadBefore = cache.containsKey(id);
    final before = cache[id];

    bool changed = false;
    if (isDelete) {
      changed = cache.remove(id) != null;
    } else {
      final normalized = Map<String, dynamic>.from(newRecord);
      if (!hadBefore || !_mapsEqual(before, normalized)) {
        cache[id] = normalized;
        changed = true;
      }
    }

    if (changed) {
      _watermarks[table] = _maxTime(_watermarks[table], _extractTimestamp(newRecord));
      _touch(table);
    }

    return changed;
  }

  bool applyDeltaRow({
    required String table,
    required Map<String, dynamic> row,
  }) {
    final cache = _tables[table];
    if (cache == null) return false;

    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return false;

    final hadBefore = cache.containsKey(id);
    final before = cache[id];

    bool changed = false;
    final normalized = Map<String, dynamic>.from(row);
    if (!hadBefore || !_mapsEqual(before, normalized)) {
      cache[id] = normalized;
      changed = true;
    }

    if (changed) {
      _watermarks[table] = _maxTime(_watermarks[table], _extractTimestamp(row));
      _touch(table);
    }

    return changed;
  }

  void upsert(String table, Map<String, dynamic> row) {
    final cache = _tables[table];
    if (cache == null) return;

    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;

    final normalized = Map<String, dynamic>.from(row);
    if (!_mapsEqual(cache[id], normalized)) {
      cache[id] = normalized;
      _watermarks[table] = _maxTime(_watermarks[table], _extractTimestamp(row));
      _touch(table);
    }
  }

  void remove(String table, String id) {
    final cache = _tables[table];
    if (cache == null) return;
    if (cache.remove(id) != null) {
      _touch(table);
    }
  }

  void _touch(String table) {
    _revisions.update(table, (value) => value + 1, ifAbsent: () => 1);
  }

  bool _mapsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key] != b[key]) return false;
    }

    return true;
  }

  DateTime? _extractTimestamp(Map<String, dynamic> row) {
    final updatedAt = row['updated_at'];
    final createdAt = row['created_at'];

    final updated = _parseDateTime(updatedAt);
    final created = _parseDateTime(createdAt);

    if (updated == null) return created;
    if (created == null) return updated;
    return updated.isAfter(created) ? updated : created;
  }

  DateTime? _parseDateTime(dynamic value) => V3CacheStore.parseDateTime(value);

  static DateTime? parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  DateTime? _maxTime(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}
