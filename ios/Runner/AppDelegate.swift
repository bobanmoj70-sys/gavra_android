import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerAlternativaNotificationCategories()

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
}
