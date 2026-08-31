import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let pendingActionDefaultsKey = "gavra_pending_remote_push_action"
  private var pushActionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerAlternativaNotificationCategories()

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.gavra013.gavra_android/push_actions",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    pushActionChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "getPendingAction" {
        result(self.consumePendingPushAction())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    captureRemotePushAction(response)
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }

  /// Ista imena/akcije kao DarwinNotificationCategory u lib/main.dart.
  /// Registracija ovde mora biti pre Flutter init da lock-screen dugmad
  /// rade i kad je app ugašena.
  private func registerAlternativaNotificationCategories() {
    let rejectOdbij = UNNotificationAction(
      identifier: "reject",
      title: "Odbij",
      options: [.destructive, .foreground]
    )
    let rejectNe = UNNotificationAction(
      identifier: "reject",
      title: "Ne",
      options: [.destructive, .foreground]
    )
    let acceptPre = UNNotificationAction(
      identifier: "accept_pre",
      title: "Prihvati termin",
      options: [.foreground]
    )
    let acceptPreFirst = UNNotificationAction(
      identifier: "accept_pre",
      title: "Prihvati prvi termin",
      options: [.foreground]
    )
    let acceptPosle = UNNotificationAction(
      identifier: "accept_posle",
      title: "Prihvati termin",
      options: [.foreground]
    )
    let acceptPosleSecond = UNNotificationAction(
      identifier: "accept_posle",
      title: "Prihvati drugi termin",
      options: [.foreground]
    )
    let acceptMesto = UNNotificationAction(
      identifier: "accept_pre",
      title: "Prihvati",
      options: [.foreground]
    )

    let categories: Set<UNNotificationCategory> = [
      UNNotificationCategory(
        identifier: "alternativa_oba",
        actions: [acceptPreFirst, acceptPosleSecond, rejectOdbij],
        intentIdentifiers: [],
        options: []
      ),
      UNNotificationCategory(
        identifier: "alternativa_pre",
        actions: [acceptPre, rejectOdbij],
        intentIdentifiers: [],
        options: []
      ),
      UNNotificationCategory(
        identifier: "alternativa_posle",
        actions: [acceptPosle, rejectOdbij],
        intentIdentifiers: [],
        options: []
      ),
      UNNotificationCategory(
        identifier: "mesto_oslobodjeno",
        actions: [acceptMesto, rejectNe],
        intentIdentifiers: [],
        options: []
      ),
    ]

    UNUserNotificationCenter.current().setNotificationCategories(categories)
  }

  private func captureRemotePushAction(_ response: UNNotificationResponse) {
    let actionId = response.actionIdentifier
    guard actionId != UNNotificationDefaultActionIdentifier,
          actionId != UNNotificationDismissActionIdentifier,
          ["accept_pre", "accept_posle", "reject"].contains(actionId) else {
      return
    }

    // Lokalne notifikacije već obrađuje flutter_local_notifications.
    guard response.notification.request.trigger is UNPushNotificationTrigger else {
      return
    }

    let payload = resolveAlternativaPayload(from: response.notification.request.content.userInfo)
    guard !payload.isEmpty else { return }

    let record: [String: String] = [
      "actionId": actionId,
      "payload": payload,
    ]
    UserDefaults.standard.set(record, forKey: pendingActionDefaultsKey)
    pushActionChannel?.invokeMethod("pushAction", arguments: record)
  }

  private func consumePendingPushAction() -> [String: String]? {
    let stored = UserDefaults.standard.dictionary(forKey: pendingActionDefaultsKey)
    UserDefaults.standard.removeObject(forKey: pendingActionDefaultsKey)
    guard let stored else { return nil }

    let actionId = stringValue(stored["actionId"])
    let payload = stringValue(stored["payload"])
    guard !actionId.isEmpty, !payload.isEmpty else { return nil }
    return ["actionId": actionId, "payload": payload]
  }

  private func resolveAlternativaPayload(from userInfo: [AnyHashable: Any]) -> String {
    let direct = userInfoString(userInfo, "payload")
    if direct.contains("|") {
      return direct
    }

    let zahtevId = userInfoString(userInfo, "zahtev_id")
    guard !zahtevId.isEmpty else { return "" }

    let altPre = userInfoString(userInfo, "alt_pre")
    let altPosle = userInfoString(userInfo, "alt_posle")
    let offerKind = userInfoString(userInfo, "offer_kind")
    if offerKind == "mesto_oslobodjeno" {
      return "\(zahtevId)|\(altPre)|\(altPosle)|mesto_oslobodjeno"
    }
    return "\(zahtevId)|\(altPre)|\(altPosle)"
  }

  private func userInfoString(_ userInfo: [AnyHashable: Any], _ key: String) -> String {
    let direct = stringValue(userInfo[key])
    if !direct.isEmpty { return direct }
    if let nested = userInfo["data"] as? [AnyHashable: Any] {
      let nestedValue = stringValue(nested[key])
      if !nestedValue.isEmpty { return nestedValue }
    }
    return ""
  }

  private func stringValue(_ value: Any?) -> String {
    if let value = value as? String {
      return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let value = value as? NSNumber {
      return value.stringValue
    }
    return ""
  }
}
