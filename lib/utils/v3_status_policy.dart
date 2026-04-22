import 'package:flutter/material.dart';

import 'v3_time_utils.dart';

class V3StatusPolicy {
  V3StatusPolicy._();

  static bool matchesSelectedSlot({
    required String? entryGrad,
    required String? entryVreme,
    required String grad,
    required String vreme,
  }) {
    final gradNorm = (entryGrad ?? '').trim().toUpperCase();
    final selectedGradNorm = grad.trim().toUpperCase();
    if (gradNorm != selectedGradNorm) return false;

    final normEntryVreme = V3TimeUtils.normalizeToHHmm(entryVreme);
    final selectedVreme = V3TimeUtils.normalizeToHHmm(vreme);
    return normEntryVreme == selectedVreme;
  }

  static String normalizeStatus(String? status) {
    final normalized = (status ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'active':
        return 'aktivan';
      case 'inactive':
      case 'deleted':
        return 'neaktivan';
      case 'otkazan':
      case 'cancelled':
        return 'otkazano';
      case 'rejected':
        return 'odbijeno';
      case 'approved':
        return 'odobreno';
      case 'pending':
        return 'obrada';
      default:
        return normalized;
    }
  }

  static String deriveOperativnaStatus({
    required Object? otkazanoAt,
    required Object? polazakAt,
  }) {
    if (isTimestampSet(otkazanoAt)) return 'otkazano';
    if (isTimestampSet(polazakAt)) return 'odobreno';
    return 'obrada';
  }

  static bool isTimestampSet(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }

  static bool isCanceledOrRejected(String? status) {
    final normalized = normalizeStatus(status);
    return normalized == 'otkazano' || normalized == 'odbijeno';
  }

  static bool isCanceled(String? status) => normalizeStatus(status) == 'otkazano';

  static bool isRejected(String? status) => normalizeStatus(status) == 'odbijeno';

  static bool isApproved(String? status) => normalizeStatus(status) == 'odobreno';

  static bool isPending(String? status) => normalizeStatus(status) == 'obrada';

  static bool isOfferLike(String? status) => normalizeStatus(status) == 'alternativa';

  static bool isDodelaAktivna(String? status) => normalizeStatus(status) == 'aktivan';

  static bool countsAsOccupied({
    String? status,
    Object? otkazanoAt,
  }) {
    if (isTimestampSet(otkazanoAt)) return false;
    if (isRejected(status)) return false;
    return true;
  }

  static bool canAssign({
    String? status,
    Object? otkazanoAt,
    Object? pokupljenAt,
  }) {
    if (!countsAsOccupied(status: status, otkazanoAt: otkazanoAt)) return false;
    if (isTimestampSet(pokupljenAt)) return false;
    return true;
  }

  static bool isActionLocked({
    String? status,
    bool pokupljen = false,
  }) {
    return pokupljen || isPending(status);
  }

  static bool isExcludedFromOptimization({
    String? status,
    bool pokupljen = false,
  }) {
    return pokupljen || isCanceledOrRejected(status);
  }

  static bool isVisibleForDisplay({
    String? status,
    bool pokupljen = false,
  }) {
    if (isCanceledOrRejected(status)) return false;
    return true;
  }

  static V3StatusBadgeUi badgeForCell({
    String? status,
    bool pokupljen = false,
  }) {
    if (pokupljen) {
      return V3StatusBadgeUi(
        color: Colors.lightBlue.shade700,
        icon: '🚗',
      );
    }

    if (isApproved(status)) {
      return V3StatusBadgeUi(
        color: Colors.green.shade600,
        icon: '✅',
      );
    }

    if (isPending(status)) {
      return V3StatusBadgeUi(
        color: Colors.orange.shade700,
        icon: '⏳',
      );
    }

    if (isOfferLike(status)) {
      return const V3StatusBadgeUi(
        color: Colors.deepOrangeAccent,
        icon: '🔄',
      );
    }

    if (isCanceledOrRejected(status)) {
      return V3StatusBadgeUi(
        color: Colors.red.shade700,
        icon: '🚫',
      );
    }

    return V3StatusBadgeUi(
      color: Colors.blueGrey.shade600,
      icon: '•',
    );
  }

  static V3StatusTextUi textForCard({
    String? status,
    bool pokupljen = false,
    bool placen = false,
  }) {
    final normalized = normalizeStatus(status);
    if (normalized == 'otkazano') {
      return const V3StatusTextUi(
        primary: Color(0xFFB71C1C),
        secondary: Color(0xFFC62828),
      );
    }

    if (pokupljen) {
      if (placen) {
        return const V3StatusTextUi(
          primary: Color(0xFF1B5E20),
          secondary: Color(0xFF2E7D32),
        );
      }
      return const V3StatusTextUi(
        primary: Color(0xFF0D47A1),
        secondary: Color(0xFF1565C0),
      );
    }

    return V3StatusTextUi(
      primary: Colors.black87,
      secondary: Colors.grey.shade700,
    );
  }

  static Color statusColor(String? status) {
    if (isApproved(status)) return Colors.green;
    if (isPending(status)) return Colors.orange;
    if (isOfferLike(status)) return Colors.orangeAccent;
    if (isCanceledOrRejected(status)) return Colors.red.shade300;
    return Colors.grey;
  }

  static ({Color borderColor, String label}) statusCardStyle(String? status) {
    final normalized = normalizeStatus(status);
    return switch (normalized) {
      'obrada' => (borderColor: Colors.amber, label: '🟡 obrada'),
      'odobreno' => (borderColor: Colors.greenAccent, label: '🟢 odobreno'),
      'alternativa' => (borderColor: Colors.orange, label: '🕒 alternativa'),
      'odbijeno' => (borderColor: Colors.redAccent, label: '🔴 odbijeno'),
      'otkazano' => (borderColor: Colors.orange, label: '⛔ otkazano'),
      _ => (borderColor: Colors.white24, label: normalized),
    };
  }

  static int statusPriority(String? status) {
    final normalized = normalizeStatus(status);
    return switch (normalized) {
      'odobreno' => 4,
      'obrada' => 3,
      'alternativa' => 2,
      'otkazano' => 1,
      _ => 0,
    };
  }

  static int displayPriority({
    String? status,
    bool pokupljen = false,
  }) {
    return statusPriority(status) + (pokupljen ? 10 : 0);
  }

  static int parseSeats(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 1;
  }

  static int compareEntriesForDisplay<T>({
    required T a,
    required T b,
    required String? currentVozacId,
    required Object? Function(T item) otkazanoAtOf,
    required Object? Function(T item) pokupljenAtOf,
    required String Function(T item) putnikIdOf,
    required String? Function(T item) assignedVozacIdForEntry,
    required String Function(String putnikId) putnikNameById,
  }) {
    int rankFor(T entry) {
      if (isTimestampSet(otkazanoAtOf(entry))) return 3;
      if (isTimestampSet(pokupljenAtOf(entry))) return 2;

      if (currentVozacId != null && currentVozacId.isNotEmpty) {
        final assigned = (assignedVozacIdForEntry(entry) ?? '').trim();
        if (assigned.isNotEmpty) {
          return assigned == currentVozacId ? 0 : 1;
        }
      }

      return 1;
    }

    final aRank = rankFor(a);
    final bRank = rankFor(b);
    if (aRank != bRank) return aRank.compareTo(bRank);

    final aIme = putnikNameById(putnikIdOf(a));
    final bIme = putnikNameById(putnikIdOf(b));
    return aIme.compareTo(bIme);
  }

  static String? assignedVozacIdForPutnik({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String putnikId,
    required String grad,
    required String vreme,
    required String datumIso,
    required String Function(Map<String, dynamic> row) vozacIdForRow,
    required bool Function(Map<String, dynamic> row) isVisibleRow,
    String vremeKolona = 'polazak_at',
  }) {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    for (final row in operativnaRows) {
      final rowGrad = row['grad']?.toString() ?? '';
      final rowVreme = V3TimeUtils.normalizeToHHmm(row[vremeKolona]?.toString());
      final rowDatum = _parseIsoDatePart(row['datum']?.toString() ?? '');
      final rowPutnikId = row['created_by']?.toString() ?? '';

      if (rowPutnikId != putnikId) continue;
      if (rowGrad != grad) continue;
      if (rowVreme != normVreme) continue;
      if (rowDatum != datumIso) continue;
      if (!isVisibleRow(row)) continue;

      final vozacId = vozacIdForRow(row).trim();
      if (vozacId.isNotEmpty) return vozacId;
    }

    return null;
  }

  static String? sharedVozacIdForTermin({
    required Iterable<Map<String, dynamic>> operativnaRows,
    required String grad,
    required String vreme,
    required String datumIso,
    required String Function(Map<String, dynamic> row) vozacIdForRow,
    required bool Function(Map<String, dynamic> row) isVisibleRow,
    String vremeKolona = 'polazak_at',
  }) {
    final normVreme = V3TimeUtils.normalizeToHHmm(vreme);

    String? zajednickiVozacId;
    var hasRows = false;

    for (final row in operativnaRows) {
      final rowGrad = row['grad']?.toString() ?? '';
      final rowVreme = V3TimeUtils.normalizeToHHmm(row[vremeKolona]?.toString());
      final rowDatum = _parseIsoDatePart(row['datum']?.toString() ?? '');

      if (rowGrad != grad) continue;
      if (rowVreme != normVreme) continue;
      if (rowDatum != datumIso) continue;
      if (!isVisibleRow(row)) continue;

      hasRows = true;
      final vozacId = vozacIdForRow(row).trim();
      if (vozacId.isEmpty) return null;

      if (zajednickiVozacId == null) {
        zajednickiVozacId = vozacId;
      } else if (zajednickiVozacId != vozacId) {
        return null;
      }
    }

    if (!hasRows) return null;
    return zajednickiVozacId;
  }

  static int countOccupiedSeatsForSlot<T>({
    required Iterable<T> items,
    required String grad,
    required String vreme,
    required String? Function(T item) gradOf,
    required String? Function(T item) vremeOf,
    required int Function(T item) seatsOf,
    required String? Function(T item) statusOf,
    required Object? Function(T item) otkazanoAtOf,
  }) {
    final gradNorm = grad.trim().toUpperCase();
    final vremeNorm = V3TimeUtils.normalizeToHHmm(vreme);

    return items.where((item) {
      final itemGrad = (gradOf(item) ?? '').trim().toUpperCase();
      if (itemGrad != gradNorm) return false;

      final itemVreme = V3TimeUtils.normalizeToHHmm(vremeOf(item));
      if (itemVreme != vremeNorm) return false;

      return countsAsOccupied(status: statusOf(item), otkazanoAt: otkazanoAtOf(item));
    }).fold(0, (sum, item) => sum + seatsOf(item));
  }

  static String _parseIsoDatePart(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(value);
    if (match != null) return match.group(1) ?? '';

    return value;
  }
}

class V3StatusBadgeUi {
  final Color color;
  final String icon;

  const V3StatusBadgeUi({
    required this.color,
    required this.icon,
  });
}

class V3StatusTextUi {
  final Color primary;
  final Color secondary;

  const V3StatusTextUi({
    required this.primary,
    required this.secondary,
  });
}
