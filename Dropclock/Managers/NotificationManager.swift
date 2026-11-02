import AppKit
import Foundation
import UserNotifications

class NotificationManager {
  static let shared = NotificationManager()

  private init() {}

  func checkForPermission(completion: @escaping () -> Void = {}) {
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized:
        completion()
      case .denied:
        return
      case .notDetermined:
        notificationCenter.requestAuthorization(options: [.alert, .sound]) {
          didAllow, error in
          if didAllow {
            completion()
          }
        }
      default:
        return
      }
    }
  }

  func dispatchNotification(timerName: String? = nil) {
    let idenfier = UUID().uuidString
    let title = timerName ?? "计时结束"
    let body: String
    if let timerName = timerName {
      body = "计时器「\(timerName)」已结束！"
    } else {
      body = "你的计时已经结束！"
    }

    let notificationCenter = UNUserNotificationCenter.current()

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = UNNotificationSound.default
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: 0.1, repeats: false)
    let request = UNNotificationRequest(
      identifier: idenfier, content: content, trigger: trigger)

    notificationCenter.removeDeliveredNotifications(withIdentifiers: [idenfier])
    notificationCenter.add(request)
  }

  func getNotificationSettings(
    completion: @escaping (UNNotificationSettings) -> Void
  ) {
    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.getNotificationSettings { settings in
      DispatchQueue.main.async {
        completion(settings)
      }
    }
  }

  /// 当前是否允许发送通知（未授权时 app 内提醒卡片仍然可见）。
  func isAuthorized(_ completion: @escaping (Bool) -> Void) {
    getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        completion(true)
      default:
        completion(false)
      }
    }
  }

  /// 跳转到「系统设置 › 通知」。
  func openSystemNotificationSettings() {
    guard
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
