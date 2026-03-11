import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../globals.dart';
import 'v2_auth_manager.dart'; // V2AdminSecurityService spojen ovde
import 'v2_notification_navigation_service.dart';

class V2RealtimeNotificationService {
  V2RealtimeNotificationService._();

  static final StreamController<Map<String, dynamic>> _notificationStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get notificationStream => _notificationStreamController.stream;

  /// Poziva se kada stigne notifikacija dok je aplikacija u foreground-u
  static void onForegroundNotification(Map<String, dynamic> data) {
    _notificationStreamController.add(data);
  }

  /// Pošalji push notifikaciju — svi tokeni se resolviraju SERVER-SIDE u edge funkciji.
  ///
  /// Načini targetiranja (jedno od):
  ///   - [putnikId]  — notifikacija jednom putniku
  ///   - [vozacIds]  — notifikacija jednom ili više vozača
  ///   - [adminNames]— notifikacija vozačima po imenu (admin lista)
  ///   - [broadcastVozaci] — notifikacija SVIM vozačima
  ///   - [tokens]    — direktni tokeni (legacy / SQL trigger pozivi)
  static Future<bool> sendPushNotification({
    required String title,
    required String body,
    String? putnikId,
    List<String>? vozacIds,
    List<String>? adminNames,
    bool broadcastVozaci = false,
    List<Map<String, dynamic>>? tokens,
    Map<String, dynamic>? data,
  }) async {
    try {
      final payload = <String, dynamic>{
        'title': title,
        'body': body,
        'data': data ?? {},
        if (putnikId != null && putnikId.isNotEmpty) 'putnik_id': putnikId,
        if (vozacIds != null && vozacIds.isNotEmpty) 'vozac_ids': vozacIds,
        if (adminNames != null && adminNames.isNotEmpty) 'admin_names': adminNames,
        if (broadcastVozaci) 'broadcast_vozaci': true,
        if (tokens != null && tokens.isNotEmpty) 'tokens': tokens,
      };

      final response = await supabase.functions.invoke(
        'send-push-notification',
        body: payload,
      );

      return response.data != null && response.data['success'] == true;
    } catch (e) {
      debugPrint('[V2RealtimeNotificationService] sendPushNotification greška: $e');
      return false;
    }
  }

  /// Pošalji notifikaciju samo adminima — tokeni se resolviraju server-side
  static Future<void> sendNotificationToAdmins({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final adminNames = V2AdminSecurityService.adminUsers;
      if (adminNames.isEmpty) return;
      await sendPushNotification(
        title: title,
        body: body,
        adminNames: adminNames,
        data: data,
      );
    } catch (e) {
      debugPrint('[V2RealtimeNotificationService] sendNotificationToAdmins greška: $e');
    }
  }

  /// Pošalji push notifikaciju putniku — tokeni se resolviraju server-side
  static Future<bool> sendNotificationToPutnik({
    required String putnikId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      return await sendPushNotification(
        title: title,
        body: body,
        putnikId: putnikId,
        data: data,
      );
    } catch (e) {
      debugPrint('[V2RealtimeNotificationService] sendNotificationToPutnik greška: $e');
      return false;
    }
  }

  static Future<void> handleInitialMessage(Map<String, dynamic>? messageData) async {
    if (messageData == null) return;
    try {
      // Emituj dogadjaj i za tap ako smo u foreground-u/background-u
      onForegroundNotification(messageData);

      await _handleNotificationTap(messageData);
    } catch (e) {
      debugPrint('[V2RealtimeNotificationService] handleInitialMessage greška: $e');
    }
  }

  /// Inicijalizacija se vrsi u V2FirebaseService — ova metoda je no-op.
  static Future<void> initialize() async {}

  static bool _foregroundListenerRegistered = false;

  /// DEPRECATED: Notifikacije se sada inicijalizuju globalno u V2FirebaseService/V2HuaweiPushService.
  /// Ova metoda ne radi ništa kako bi se sprečili dupli listeneri.
  static void listenForForegroundNotifications() {
    if (_foregroundListenerRegistered) return;
    _foregroundListenerRegistered = true;
  }

  static Future<void> subscribeToDriverTopics(String? driverId) async {
    if (driverId == null || driverId.isEmpty) return;
    try {
      if (Firebase.apps.isEmpty) return;
      final messaging = FirebaseMessaging.instance;
      await messaging.subscribeToTopic('gavra_driver_${driverId.toLowerCase()}');
      await messaging.subscribeToTopic('gavra_all_drivers');
    } catch (e) {
      debugPrint('[V2RealtimeNotificationService] subscribeToDriverTopics greška: $e');
    }
  }

  static Future<bool> requestNotificationPermissions() async {
    try {
      if (Firebase.apps.isEmpty) return false;
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[V2RealtimeNotificationService] requestNotificationPermissions greška: $e');
      return false;
    }
  }

  static Future<void> _handleNotificationTap(Map<String, dynamic> messageData) async {
    try {
      final notificationType = messageData['type'] ?? 'unknown';

      if (notificationType == 'transport_started' ||
          notificationType == 'v2_odobreno' ||
          notificationType == 'v2_odbijeno' ||
          notificationType == 'v2_alternativa') {
        await V2NotificationNavigationService.navigateToPassengerProfile();
        return;
      }

      if (notificationType == 'vozac_krenuo') {
        await V2NotificationNavigationService.navigateToVozacScreen();
        return;
      }

      if (notificationType == 'pin_zahtev' || notificationType == 'v2_obrada') {
        await V2NotificationNavigationService.navigateToPinZahtevi();
        return;
      }

      final putnikDataString = messageData['V2Putnik'] as String?;
      if (putnikDataString != null) {
        final Map<String, dynamic> putnikData = jsonDecode(putnikDataString) as Map<String, dynamic>;
        await V2NotificationNavigationService.navigateToPassenger(
          type: notificationType,
          putnikData: putnikData,
        );
      }
    } catch (e) {
      debugPrint('[V2RealtimeNotificationService] _handleNotificationTap greška: $e');
    }
  }
}
