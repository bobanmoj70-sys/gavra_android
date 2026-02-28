import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'v2_local_notification_service.dart';

// This file exposes two background handlers:
//  - firebaseMessagingBackgroundHandler(RemoteMessage) which is registered
//    with Firebase Messaging plugin for FCM background delivery.
//  - backgroundNotificationHandler(Map<String,dynamic>) which is provider
//    agnostic and can be used for Huawei or other push providers.

// Top-level background handler required by Firebase Messaging plugin
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    final payload = Map<String, dynamic>.from(message.data);
    await backgroundNotificationHandler(payload);
  } catch (e) {
    debugPrint('�Y"� Error in Firebase background handler: $e');
  }
}

// Generic background notification handler used for non-Firebase pushes.
// Accepts a plain JSON payload map to remain provider-agnostic.
Future<void> backgroundNotificationHandler(Map<String, dynamic> payload) async {
  try {
    final title = payload['title'] as String? ?? 'Gavra Notification';
    final body = payload['body'] as String? ??
        (payload['message'] as String?) ??
        'Nova notifikacija';

    // �Y>�️ FIX: Umesto samo payload['data'], prosle�'ujemo ceo payload.
    // FCM postavlja sve podatke direktno u message.data, tako da je payload ve�? 'data' mapa.
    await LocalNotificationService.showNotificationFromBackground(
      title: title,
      body: body,
      payload: jsonEncode(payload),
    );
  } catch (e) {
    debugPrint('�s�️ Error handling background notification: $e');
  }
}


