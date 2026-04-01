import 'package:flutter/material.dart';

import 'v3_status_filters.dart';

class V3StatusPresentation {
  V3StatusPresentation._();

  static V3StatusBadgeStyle forCell({
    String? status,
    bool pokupljen = false,
  }) {
    if (pokupljen) {
      return V3StatusBadgeStyle(
        color: Colors.lightBlue.shade700,
        icon: '🚗',
      );
    }

    if (V3StatusFilters.isApproved(status)) {
      return V3StatusBadgeStyle(
        color: Colors.green.shade600,
        icon: '✅',
      );
    }

    if (V3StatusFilters.isPending(status)) {
      return V3StatusBadgeStyle(
        color: Colors.orange.shade700,
        icon: '⏳',
      );
    }

    if (V3StatusFilters.isOfferLike(status)) {
      return const V3StatusBadgeStyle(
        color: Colors.deepOrangeAccent,
        icon: '🔄',
      );
    }

    if (V3StatusFilters.isCanceledOrRejected(status)) {
      return V3StatusBadgeStyle(
        color: Colors.red.shade700,
        icon: '🚫',
      );
    }

    return V3StatusBadgeStyle(
      color: Colors.blueGrey.shade600,
      icon: '•',
    );
  }

  static V3StatusTextStyle forCardText({
    String? status,
    bool pokupljen = false,
    bool placen = false,
  }) {
    final normalized = V3StatusFilters.normalizeStatus(status);
    if (normalized == 'otkazano') {
      return const V3StatusTextStyle(
        primary: Color(0xFFB71C1C),
        secondary: Color(0xFFC62828),
      );
    }

    if (pokupljen) {
      if (placen) {
        return const V3StatusTextStyle(
          primary: Color(0xFF1B5E20),
          secondary: Color(0xFF2E7D32),
        );
      }
      return const V3StatusTextStyle(
        primary: Color(0xFF0D47A1),
        secondary: Color(0xFF1565C0),
      );
    }

    return V3StatusTextStyle(
      primary: Colors.black87,
      secondary: Colors.grey.shade700,
    );
  }
}

class V3StatusBadgeStyle {
  final Color color;
  final String icon;

  const V3StatusBadgeStyle({
    required this.color,
    required this.icon,
  });
}

class V3StatusTextStyle {
  final Color primary;
  final Color secondary;

  const V3StatusTextStyle({
    required this.primary,
    required this.secondary,
  });
}
