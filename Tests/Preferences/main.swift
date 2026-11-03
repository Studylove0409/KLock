import AppKit
import EventKit
import Foundation

// 系统权限由测试替身控制；PreferencesViewModel 和 UserDefaults 均使用真实实现。
final class RemindersManager {
  static var grantedStatus: EKAuthorizationStatus {
    if #available(macOS 14, *) { return .fullAccess }
    return .authorized
  }

  static let shared = RemindersManager()
  static let selectedReminderListKey = "SelectedReminderList"

  var status: EKAuthorizationStatus = .notDetermined
  var statusAfterRequest: EKAuthorizationStatus = .denied
  var calendars: [EKCalendar] = []
  var requestCount = 0
  var holdRequest = false
  var pendingRequest: CheckedContinuation<Bool, Never>?

  func checkAuthorizationStatus() -> EKAuthorizationStatus { status }

  private func isFullAccess(_ value: EKAuthorizationStatus) -> Bool {
    if #available(macOS 14, *) {
      return value == .fullAccess
    }
    return value == .authorized
  }

  func requestAccess() async -> Bool {
    requestCount += 1
    if holdRequest {
      return await withCheckedContinuation { pendingRequest = $0 }
    }
    status = statusAfterRequest
    return isFullAccess(status)
  }

  func fetchReminderLists() -> [EKCalendar] {
    isFullAccess(status) ? calendars : []
  }
}

final class NotificationManager {
  static let shared = NotificationManager()
  var authorized = false
  func isAuthorized(_ completion: @escaping (Bool) -> Void) { completion(authorized) }
  func openSystemNotificationSettings() {}
}

final class SoundManager {
  static let shared = SoundManager()
  func availableAlarmSounds() -> [String] { [] }
}

@main
struct PreferencesTests {
  @MainActor
  static func main() async {
    var failures = 0
    func expect(_ condition: Bool, _ label: String) {
      if condition {
        print("  ✓ \(label)")
      } else {
        print("  ✗ \(label)")
        failures += 1
      }
    }

    let defaults = UserDefaults.standard
    let manager = RemindersManager.shared
    PreferencesViewModel.registerDefaultPreferences()
    expect(defaults.bool(forKey: "allowFiveMinuteMode"), "打开设置之前启用 5 分钟模式")
    expect(defaults.bool(forKey: "showDragIndicator"), "打开设置之前启用拖拽连线")
    let viewModel = PreferencesViewModel()
    await Task.yield()

    print("首次偏好和已保存选择")
    expect(viewModel.allowFiveMinuteMode, "首次读取时开启 5 分钟模式")
    expect(viewModel.showDragIndicator, "首次读取时显示拖拽连线")
    expect(viewModel.deleteReminders, "首次读取时开启同步删除")
    expect(viewModel.shortTimerThresholdMinutes == 1, "首次读取时短时阈值为 1 分钟")
    expect(defaults.bool(forKey: "allowFiveMinuteMode"), "其他功能读取到开启的 5 分钟模式")
    expect(defaults.bool(forKey: "showDragIndicator"), "其他功能读取到开启的拖拽连线")
    expect(defaults.double(forKey: "shortTimerThresholdMinutes") == 1, "其他功能读取到合法的短时阈值")

    defaults.set(false, forKey: "allowFiveMinuteMode")
    defaults.set(false, forKey: "showDragIndicator")
    defaults.set(false, forKey: "deleteReminders")
    defaults.set(12.0, forKey: "shortTimerThresholdMinutes")
    viewModel.loadPreferences()
    expect(!viewModel.allowFiveMinuteMode, "保留用户关闭的 5 分钟模式")
    expect(!viewModel.showDragIndicator, "保留用户关闭的拖拽连线")
    expect(!viewModel.deleteReminders, "保留用户关闭的同步删除")
    expect(viewModel.shortTimerThresholdMinutes == 12, "保留用户保存的阈值")
    defaults.set(0.0, forKey: "shortTimerThresholdMinutes")
    viewModel.loadPreferences()
    expect(viewModel.shortTimerThresholdMinutes == 1, "旧版保存的 0 分钟修正为 1 分钟")
    expect(defaults.double(forKey: "shortTimerThresholdMinutes") == 1, "其他功能读取修正后的阈值")
    defaults.set(90.0, forKey: "shortTimerThresholdMinutes")
    viewModel.loadPreferences()
    expect(viewModel.shortTimerThresholdMinutes == 60, "超出上限的阈值修正为 60 分钟")

    print("提醒事项授权")
    let eventStore = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = "测试列表"
    let selectedCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
    selectedCalendar.title = "已选列表"
    manager.calendars = [calendar, selectedCalendar]
    defaults.set(selectedCalendar.calendarIdentifier, forKey: RemindersManager.selectedReminderListKey)
    manager.status = RemindersManager.grantedStatus
    viewModel.allowReminders = true
    defaults.set(true, forKey: "allowReminders")
    await viewModel.ensureReminderAccessAndFetchLists()
    expect(viewModel.reminderLists.count == 2, "已授权时加载提醒列表")
    expect(viewModel.selectedList?.calendarIdentifier == selectedCalendar.calendarIdentifier,
      "已授权时恢复用户选中的列表")

    manager.status = .denied
    await viewModel.ensureReminderAccessAndFetchLists()
    expect(!viewModel.allowReminders, "权限被收回时关闭提醒开关")
    expect(!defaults.bool(forKey: "allowReminders"), "权限被收回时保存关闭状态")
    expect(viewModel.reminderLists.isEmpty, "权限被收回时清空列表")
    expect(viewModel.selectedList == nil, "权限被收回时清空当前选择")
    expect(viewModel.reminderAccessIssue != nil, "权限被拒绝时展示原因")

    manager.status = RemindersManager.grantedStatus
    NotificationManager.shared.authorized = true
    viewModel.refreshPermissionStatus()
    expect(viewModel.notificationsAuthorized == true, "回到应用时重新读取通知权限")
    expect(viewModel.reminderAccessIssue == nil, "恢复授权后不再显示拒绝原因")
    expect(viewModel.reminderLists.count == 2, "恢复授权后重新加载提醒列表")
    expect(viewModel.selectedList?.calendarIdentifier == selectedCalendar.calendarIdentifier,
      "恢复授权后保留原先选择的列表")
    expect(!viewModel.allowReminders, "恢复授权后保留关闭状态，等待用户重新开启")
    NotificationManager.shared.authorized = false
    viewModel.refreshPermissionStatus()
    expect(viewModel.notificationsAuthorized == false, "通知权限收回后刷新为未允许")

    manager.calendars = []
    viewModel.refreshPermissionStatus()
    expect(viewModel.reminderLists.isEmpty, "刷新后反映已删除的列表")
    expect(viewModel.selectedList == nil, "列表消失后清空原先的选择")

    manager.status = .notDetermined
    manager.statusAfterRequest = .denied
    viewModel.allowReminders = true
    defaults.set(true, forKey: "allowReminders")
    await viewModel.ensureReminderAccessAndFetchLists()
    expect(!viewModel.allowReminders, "首次请求被拒绝时关闭提醒开关")
    expect(!defaults.bool(forKey: "allowReminders"), "首次请求被拒绝时保存关闭状态")
    expect(viewModel.reminderAccessIssue != nil, "首次请求被拒绝时展示原因")

    manager.status = .restricted
    viewModel.allowReminders = true
    viewModel.refreshPermissionStatus()
    expect(!viewModel.allowReminders && viewModel.reminderAccessIssue != nil,
      "系统限制访问时关闭开关并展示原因")

    if #available(macOS 14, *) {
      manager.status = .writeOnly
      viewModel.allowReminders = true
      viewModel.refreshPermissionStatus()
      expect(!viewModel.allowReminders && viewModel.reminderAccessIssue != nil,
        "仅有写入权限时说明无法读取提醒列表")
    }

    manager.status = .notDetermined
    manager.statusAfterRequest = .notDetermined
    viewModel.allowReminders = true
    await viewModel.ensureReminderAccessAndFetchLists()
    expect(!viewModel.allowReminders && viewModel.reminderAccessIssue != nil,
      "授权请求失败且状态未确定时关闭开关并展示原因")

    let previousRequestCount = manager.requestCount
    viewModel.refreshPermissionStatus()
    expect(manager.requestCount == previousRequestCount, "回到应用时不主动弹出授权请求")

    manager.holdRequest = true
    manager.status = .notDetermined
    manager.statusAfterRequest = RemindersManager.grantedStatus
    manager.calendars = [calendar]
    viewModel.allowReminders = true
    defaults.set(true, forKey: "allowReminders")
    let request = Task { @MainActor in
      await viewModel.ensureReminderAccessAndFetchLists()
    }
    var pending = manager.pendingRequest
    for _ in 0..<200 where pending == nil {
      try? await Task.sleep(nanoseconds: 1_000_000)
      pending = manager.pendingRequest
    }
    guard let pending else {
      print("  ✗ 没有启动待处理的授权请求")
      exit(1)
    }
    let requestsWhilePending = manager.requestCount
    viewModel.refreshPermissionStatus()
    await viewModel.ensureReminderAccessAndFetchLists()
    expect(viewModel.allowReminders, "授权弹窗处理中刷新不会关闭开关")
    expect(manager.requestCount == requestsWhilePending, "授权弹窗处理中不会重复请求")
    viewModel.allowReminders = false
    defaults.set(false, forKey: "allowReminders")
    manager.status = RemindersManager.grantedStatus
    pending.resume(returning: true)
    await request.value
    expect(!viewModel.allowReminders, "授权返回时保留用户等待期间的关闭选择")

    if failures > 0 {
      print("失败 \(failures) 项")
      exit(1)
    }
    print("全部通过")
  }
}
