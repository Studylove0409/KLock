import AppKit
import EventKit
import SwiftUI
import UserNotifications

@main
struct MenuBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  
  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem?
  let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
  }()
  var baseTime = Date()
  
  internal var dragTimeInterval: TimeInterval = 0
  internal var dragStartLocation: CGPoint?
  internal var dragLineView: DragLineView?
  internal var dragLineWindow: NSWindow?
  internal let MinuteThreshold: CGFloat = 130
  internal let ThirtySecondThreshold: CGFloat = 80
  internal let SecondThreshold: CGFloat = 50
  
  private var statusIconUpdateTimer: Timer?
  private var timer: Timer?
  /// 循环闹铃时已结束、但需要留在列表里等用户手动停止的计时器。
  private var finishedTimerIds: Set<UUID> = []
  /// 屏幕中央的强提醒卡片
  private var reminderAlertPanel: ReminderAlertPanel?
  private var reminderAlertTimerId: UUID?
  private static let snoozeDuration: TimeInterval = 5 * 60
  private var activeTimers:
  [(
    id: UUID, name: String?, startTime: Date, duration: TimeInterval,
    timer: Timer, reminderId: String?
  )] = []
  internal var pendingTimerData: (startTime: Date, duration: TimeInterval)?
  
  private var nameInputPanel: NameInputPanel?
  internal var dragTimerPanel: DragTimerPanel?
  
  internal var endTime: Date?
  private var isMenuOpen = false
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(
      withLength: NSStatusItem.variableLength)
    if let button = statusItem?.button {
      updateStatusIcon()
      setupDrag(for: button)
    }
    NotificationManager.shared.checkForPermission()
    RemindersManager.migrateSelectedReminderListIfNeeded()
    loadSavedTimers()
    
    updateMenu()
    
    startStatusIconUpdateTimer()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(menuWillOpen(_:)),
      name: NSMenu.didBeginTrackingNotification,
      object: nil
    )
    
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(menuWillClose(_:)),
      name: NSMenu.didEndTrackingNotification,
      object: nil
    )
  }
  
  func applicationWillTerminate(_ notification: Notification) {
    dragTimerPanel?.cleanup()
    nameInputPanel?.cleanup()
  }
  
  private func saveTimers() {
    let timersToSave = activeTimers.map { timer -> SavedTimer in
      return SavedTimer(
        id: timer.id.uuidString,
        name: timer.name,
        startTime: timer.startTime,
        duration: timer.duration,
        reminderId: timer.reminderId
      )
    }
    
    do {
      let data = try JSONEncoder().encode(timersToSave)
      UserDefaults.standard.set(data, forKey: "SavedTimers")
    } catch {
      print("Failed to save timers: \(error)")
    }
  }
  
  private func loadSavedTimers() {
    guard let data = UserDefaults.standard.data(forKey: "SavedTimers") else {
      return
    }
    
    do {
      let savedTimers = try JSONDecoder().decode([SavedTimer].self, from: data)
      
      for savedTimer in savedTimers {
        let timerId = UUID(uuidString: savedTimer.id) ?? UUID()
        let endTime = savedTimer.startTime.addingTimeInterval(
          savedTimer.duration)
        let remainingTime = endTime.timeIntervalSinceNow

        let timerObj = makeTimerCheck(id: timerId, endAt: endTime)

        activeTimers.append(
          (
            id: timerId,
            name: savedTimer.name,
            startTime: savedTimer.startTime,
            duration: savedTimer.duration,
            timer: timerObj,
            reminderId: savedTimer.reminderId
          ))

        if remainingTime <= 0 {
          print(
            "Timer \(timerId) expired while app was not running. Triggering notification..."
          )
        }
      }
      
      updateStatusIcon()
    } catch {
      print("Failed to load timers: \(error)")
    }
  }
  
  @objc private func menuWillOpen(_ notification: Notification) {
    guard let menu = notification.object as? NSMenu, menu == statusItem?.menu
    else { return }
    isMenuOpen = true
    startMenuRefreshTimer()
  }
  
  @objc private func menuWillClose(_ notification: Notification) {
    guard let menu = notification.object as? NSMenu, menu == statusItem?.menu
    else { return }
    isMenuOpen = false
    stopMenuRefreshTimer()
  }
  
  private var menuRefreshTimer: Timer?
  
  private func startMenuRefreshTimer() {
    stopMenuRefreshTimer()
    menuRefreshTimer = Timer.scheduledTimer(
      withTimeInterval: 1.0, repeats: true
    ) { [weak self] _ in
      guard let self = self, self.isMenuOpen else { return }
      self.updateMenu()
    }
  }
  
  private func stopMenuRefreshTimer() {
    menuRefreshTimer?.invalidate()
    menuRefreshTimer = nil
  }
  
  internal func showNameInputField() {
    nameInputPanel?.cleanup()
    nameInputPanel = NameInputPanel(delegate: self)
    nameInputPanel?.show(at: NSEvent.mouseLocation)
  }
  
  /// 菜单栏里分配给计时器名称的宽度预算（pt）。
  private static let menuBarNameWidth: CGFloat = 120
  private static let menuBarNameFont = NSFont.systemFont(
    ofSize: 13, weight: .medium)

  private var truncatedNameCache: (name: String, maxWidth: CGFloat, result: String)?

  /// 按渲染宽度截断：原来按字符数算，中文一个字约占两个英文宽度，会撑爆菜单栏。
  /// 状态栏每秒刷新，这里缓存上次结果，避免重复做字符串测量。
  private func truncatedName(_ name: String, maxWidth: CGFloat) -> String {
    if let cached = truncatedNameCache, cached.name == name,
      cached.maxWidth == maxWidth
    {
      return cached.result
    }

    let result = TimerTextFormatter.truncated(
      name, maxWidth: maxWidth, font: Self.menuBarNameFont)
    truncatedNameCache = (name, maxWidth, result)
    return result
  }

  /// 正在计时的数量（不含循环闹铃结束后残留的条目）。
  private var runningTimerCount: Int {
    activeTimers.reduce(0) { count, timer in
      count + (finishedTimerIds.contains(timer.id) ? 0 : 1)
    }
  }

  internal func updateStatusIcon() {
    if UserDefaults.standard.bool(forKey: "showNextTimerInMenuBar")
      && runningTimerCount > 0
    {

      let nextTimer = activeTimers
        .filter { !finishedTimerIds.contains($0.id) }
        .min { timer1, timer2 in
          let endTime1 = timer1.startTime.addingTimeInterval(timer1.duration)
          let endTime2 = timer2.startTime.addingTimeInterval(timer2.duration)
          return endTime1 < endTime2
        }
      
      if let timer = nextTimer {
        let now = Date()
        let endTime = timer.startTime.addingTimeInterval(timer.duration)
        let remainingTime = endTime.timeIntervalSince(now)
        
        if remainingTime > 0 {
          let formattedTime = TimerTextFormatter.duration(remainingTime)
          let displayName = truncatedName(
            timer.name ?? "计时器", maxWidth: Self.menuBarNameWidth)
          let displayText = "\(displayName): \(formattedTime)"
          
          statusItem?.button?.image = nil
          statusItem?.button?.title = displayText
          
          if let button = statusItem?.button {
            button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
          }
          
          return
        }
      }
    }
    
    if UserDefaults.standard.bool(forKey: "useCustomMenuBarSymbol") || UserDefaults.standard.bool(forKey: "useAlternativeMenuBarIcon") {
      statusItem?.button?.title = ""
      let symbolName: String
      if UserDefaults.standard.bool(forKey: "useCustomMenuBarSymbol") && (UserDefaults.standard.string(forKey: "customMenuBarSymbol")) != "" {
        symbolName = UserDefaults.standard.string(forKey: "customMenuBarSymbol") ?? "arrow.circlepath"
      }
      else {
        symbolName = "paperplane.circle"
      }
      if let symbolImage = NSImage(
        systemSymbolName: symbolName,
        accessibilityDescription: nil)
      {
        symbolImage.size = NSSize(width: 18, height: 18)
        statusItem?.button?.image = symbolImage
      } else {
        print("SF Symbol not found.")
      }
    }
    else if UserDefaults.standard.bool(forKey: "useCustomMenuBarIcon") {
      statusItem?.button?.image = nil
      statusItem?.button?.title = UserDefaults.standard.string(forKey: "customMenuBarWord") ?? ""
      if let button = statusItem?.button {
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
      }
    }
    else {
      if runningTimerCount > 0 {
        let symbolName: String
        if #available(macOS 15.3, *) {
          symbolName = "arrow.trianglehead.counterclockwise.rotate.90"
        } else {
          symbolName = "arrow.circlepath"
        }
        
        if let symbolImage = NSImage(
          systemSymbolName: symbolName,
          accessibilityDescription: nil)
        {
          let symbolSize = NSSize(width: 16, height: 16)
          symbolImage.size = symbolSize
          symbolImage.isTemplate = true  // Ensure template image
          
          let text = runningTimerCount > 9 ? "+" : "\(runningTimerCount)"
          let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium)
          ]
          let attributedString = NSAttributedString(
            string: text, attributes: attributes)
          let textSize = attributedString.size()
          
          let combinedImage = NSImage(size: symbolSize)
          combinedImage.lockFocus()
          
          symbolImage.draw(
            at: NSPoint.zero, from: NSRect(origin: .zero, size: symbolSize),
            operation: .sourceOver, fraction: 1)
          
          let textPosition = NSPoint(
            x: (symbolSize.width - textSize.width) / 2,
            y: (symbolSize.height - textSize.height) / 2)
          attributedString.draw(at: textPosition)  // Draw attributed string directly
          
          combinedImage.unlockFocus()
          combinedImage.isTemplate = true  // Ensure template image
          
          statusItem?.button?.image = combinedImage
          statusItem?.button?.title = ""
        } else {
          print("SF Symbol not found.")
          statusItem?.button?.title = "\(activeTimers.count)"
          statusItem?.button?.image = nil
        }
      } else {
        statusItem?.button?.title = ""
        let symbolName: String
        if #available(macOS 15.3, *) {
          symbolName = "clock.arrow.trianglehead.counterclockwise.rotate.90"
        } else {
          symbolName = "clock.arrow.circlepath"
        }
        if let symbolImage = NSImage(
          systemSymbolName: symbolName,
          accessibilityDescription: nil)
        {
          symbolImage.size = NSSize(width: 18, height: 18)
          statusItem?.button?.image = symbolImage
        } else {
          print("SF Symbol not found.")
        }
      }
    }
  }
  
  internal func createDragTimerPanel() {
    dragTimerPanel?.cleanup()
    dragTimerPanel = DragTimerPanel()
    dragTimerPanel?.show()
  }
  
  internal func updateDragTimerWindow(
    withText text: String, endTimeText: String, atPoint point: NSPoint
  ) {
    dragTimerPanel?.update(timerText: text, endTimeText: endTimeText, at: point)
  }
  
  internal func removeDragTimerPanel() {
    dragTimerPanel?.cleanup()
    dragTimerPanel = nil
  }
  
  private func startStatusIconUpdateTimer() {
    statusIconUpdateTimer?.invalidate()
    if UserDefaults.standard.bool(forKey: "showNextTimerInMenuBar") {
      statusIconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        self?.baseTime = Date()
        self?.updateStatusIcon()
      }
    } else {
      statusIconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.baseTime = Date()
        self?.updateStatusIcon()
      }
    }
  }
  
  /// 每秒检查是否到点。
  /// 原来用一个整段时长的单次 Timer，系统睡眠或主线程卡顿后回调会迟触发，
  /// 而界面时间是由 endTime 算的，两者会不一致，所以改成轮询判断。
  private func makeTimerCheck(id: UUID, endAt: Date) -> Timer {
    let interval = min(1.0, max(0.2, endAt.timeIntervalSinceNow))
    return Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      [weak self] _ in
      guard let self = self, Date() >= endAt else { return }
      self.timerFinished(id: id)
    }
  }

  internal func startOneTimeTimer(name: String?) {
    if let timerData = pendingTimerData
        ?? (dragTimeInterval > 0 ? (Date(), dragTimeInterval) : nil)
    {
      let timerId = UUID()
      let reminderId: String? = nil

      // 以真正开始计时的时刻为准。开启自定义命名时，输入名字的耗时
      // 不应该从时长里被扣掉（否则 1 分钟会显示成 00:57）。
      let startTime = Date()
      let endAt = startTime.addingTimeInterval(timerData.duration)
      let timerObj = makeTimerCheck(id: timerId, endAt: endAt)
      
      if UserDefaults.standard.bool(forKey: "allowReminders") {
        if !UserDefaults.standard.bool(forKey: "ignoreShortTimers")
            || timerData.duration
            > (UserDefaults.standard.double(
              forKey: "shortTimerThresholdMinutes") * 60)
        {
          let reminderTitle = name ?? "计时器 \(activeTimers.count + 1)"
          let reminderNotes =
          "你的 \(Int(timerData.duration / 60)) 分钟计时已结束。"
          let reminderTime = Date().addingTimeInterval(timerData.duration)

          // 首次使用会在这里弹出「提醒事项」授权框，授权成功后再创建。
          Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
              let createdId = try await RemindersManager.shared
                .createReminderAfterEnsuringAccess(
                  title: reminderTitle, notes: reminderNotes,
                  dueDate: reminderTime)
              self.assignReminderId(createdId, to: timerId)
            } catch {
              print("Failed to create reminder: \(error.localizedDescription)")
              self.showReminderError(error)
            }
          }
        }
      }
      
      activeTimers.append(
        (
          id: timerId,
          name: name,
          startTime: startTime,
          duration: timerData.duration,
          timer: timerObj,
          reminderId: reminderId
        ))
      
      updateStatusIcon()
      updateMenu()
      saveTimers()
    }
    
    pendingTimerData = nil
    nameInputPanel?.cleanup()
    nameInputPanel = nil
  }

  /// 提醒事项创建失败时给出可见反馈，避免只写日志导致用户完全无感。
  private func showReminderError(_ error: Error, action: String = "创建") {
    let message: String
    if let reminderError = error as? RemindersError {
      switch reminderError {
      case .accessDenied:
        message =
          "没有「提醒事项」的访问权限。请到「系统设置 › 隐私与安全性 › 提醒事项」中允许 Dropclock。"
      case .noReminderListSelected:
        message = "没有可用的提醒列表。请在偏好设置的「提醒」分页中重新选择一个列表。"
      case .reminderCreationFailed(let underlying):
        message = "创建提醒失败：\(underlying.localizedDescription)"
      case .reminderDeletionFailed(let underlying):
        message = "删除提醒失败：\(underlying.localizedDescription)"
      case .reminderNotFound:
        message = "找不到对应的提醒，它可能已在「提醒事项」中被删除。"
      }
    } else {
      message = error.localizedDescription
    }

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "无法\(action)提醒事项"
      alert.informativeText = message
      alert.alertStyle = .warning
      alert.addButton(withTitle: "好")
      alert.runModal()
    }
  }

  /// 提醒是异步创建的，成功后把 ID 回写到对应计时器，删除计时器时才能同步删提醒。
  private func assignReminderId(_ reminderId: String, to timerId: UUID) {
    guard let index = activeTimers.firstIndex(where: { $0.id == timerId })
    else { return }
    activeTimers[index].reminderId = reminderId
    saveTimers()
  }

  private func timerFinished(id: UUID) {
    if let index = activeTimers.firstIndex(where: { $0.id == id }) {
      let timer = activeTimers[index]
      let timerName = timer.name
      timer.timer.invalidate()
      NotificationManager.shared.dispatchNotification(timerName: timerName)
      let defaults = UserDefaults.standard
      let shouldLoopAlarm = defaults.bool(forKey: "playAlarmSound")
        && defaults.bool(forKey: "loopAlarmUntilStopped")
      SoundManager.shared.playSelectedAlarmIfEnabled(loop: shouldLoopAlarm)

      if shouldLoopAlarm {
        // 循环闹铃时保留在列表里并标记为已结束，用户点「删除」即可停止。
        finishedTimerIds.insert(id)
      } else {
        activeTimers.remove(at: index)
      }

      showReminderAlert(
        timerId: id, name: timerName, duration: timer.duration)
    }

    updateStatusIcon()
    updateMenu()
    saveTimers()
  }
  
  // MARK: - 结束提醒

  private func showReminderAlert(
    timerId: UUID, name: String?, duration: TimeInterval
  ) {
    let minutes = Int(duration / 60)
    let detail =
      duration < 60
      ? "\(Int(duration)) 秒的计时已结束"
      : "\(minutes) 分钟的计时已结束"

    let panel = ReminderAlertPanel()
    reminderAlertPanel = panel
    reminderAlertTimerId = timerId

    panel.show(
      timerName: name ?? "计时器",
      detail: detail,
      snoozeTitle: "稍后提醒 5 分钟",
      onClose: { [weak self] in
        self?.dismissReminderAlert(timerId: timerId)
      },
      onSnooze: { [weak self] in
        self?.snoozeReminder(timerId: timerId, name: name)
      })
  }

  private func dismissReminderAlert(timerId: UUID) {
    reminderAlertPanel = nil
    reminderAlertTimerId = nil
    SoundManager.shared.stopActiveSound()
    removeTimerEntry(id: timerId)
  }

  private func snoozeReminder(timerId: UUID, name: String?) {
    dismissReminderAlert(timerId: timerId)
    pendingTimerData = (Date(), Self.snoozeDuration)
    startOneTimeTimer(name: name)
  }

  /// 从列表里彻底移除某个计时器（含已结束仍残留的条目）。
  private func removeTimerEntry(id: UUID) {
    guard let index = activeTimers.firstIndex(where: { $0.id == id })
    else { return }
    activeTimers[index].timer.invalidate()
    activeTimers.remove(at: index)
    finishedTimerIds.remove(id)
    saveTimers()
    updateStatusIcon()
    updateMenu()
  }

  @objc func cancelTimer(sender: NSMenuItem) {
    // 按 UUID 定位，避免菜单每秒重建期间计时器列表变动导致删错行。
    guard let timerId = sender.representedObject as? UUID,
      let timerIndex = activeTimers.firstIndex(where: { $0.id == timerId })
    else {
      return
    }
    
    let timerToRemove = activeTimers[timerIndex]
    
    if UserDefaults.standard.bool(forKey: "deleteReminders") {
      if let reminderId = timerToRemove.reminderId {
        Task {
          do {
            try await RemindersManager.shared.deleteReminder(
              withIdentifier: reminderId)
          } catch {
            print("Failed to delete reminder: \(error.localizedDescription)")
            self.showReminderError(error, action: "删除")
          }
        }
      }
    }
    
    timerToRemove.timer.invalidate()
    finishedTimerIds.remove(timerId)
    activeTimers.remove(at: timerIndex)

    // 如果屏幕上的提醒卡片正属于这个计时器，一并关掉。
    if reminderAlertTimerId == timerId {
      reminderAlertPanel?.close()
      reminderAlertPanel = nil
      reminderAlertTimerId = nil
    }

    SoundManager.shared.stopActiveSound()
    saveTimers()
    updateStatusIcon()
    
    if sender.menu != nil && !sender.isHidden {
      sender.menu?.cancelTracking()
    }
    
    updateMenu()
  }
  
  @objc func preferences() {
    PreferencesWindowController.shared.showWindow()
  }
  
  @objc func quit() {
    NSApplication.shared.terminate(nil)
  }
  
  private var lastMenuSignature: String?

  /// 菜单内容指纹：只有内容真的变了才重建，避免每秒重建带来的闪烁和开销。
  private func menuSignature() -> String {
    let items = activeTimers.map { timer -> String in
      let remaining = timer.startTime.addingTimeInterval(timer.duration)
        .timeIntervalSince(Date())
      let state = finishedTimerIds.contains(timer.id) ? "F" : "R"
      return
        "\(timer.id.uuidString)#\(Int(max(0, remaining)))#\(state)#\(timer.name ?? "")"
    }
    return "\(activeTimers.count)|" + items.joined(separator: ",")
  }

  private func updateMenu() {
    let signature = menuSignature()
    guard signature != lastMenuSignature else { return }
    lastMenuSignature = signature

    let menu = NSMenu()
    
    if activeTimers.count > 0 {
      menu.addItem(
        NSMenuItem(title: "进行中的计时器", action: nil, keyEquivalent: ""))
      
      for (index, timerInfo) in activeTimers.enumerated() {
        let remainingTime = timerInfo.startTime.addingTimeInterval(
          timerInfo.duration
        ).timeIntervalSince(Date())
        let formattedTime = finishedTimerIds.contains(timerInfo.id)
          ? "已结束"
          : TimerTextFormatter.duration(remainingTime)

        let displayName = timerInfo.name ?? "计时器 \(index + 1)"
        let menuItem = NSMenuItem()

        let customView = HoverView(
          normalText: "\(displayName): \(formattedTime)",
          hoverText: "删除",
          frame: NSRect(x: 0, y: 0, width: 250, height: 22),
          representedObject: timerInfo.id,
          target: self,
          action: #selector(cancelTimer(sender:))
        )
        menuItem.view = customView
        
        menu.addItem(menuItem)
      }
      
      menu.addItem(NSMenuItem.separator())
    }
    
    menu.addItem(
      NSMenuItem(
        title: "偏好设置…", action: #selector(preferences), keyEquivalent: ","
      ))
    menu.addItem(
      NSMenuItem(
        title: "退出 Dropclock", action: #selector(quit), keyEquivalent: "q"))
    
    statusItem?.menu = menu
  }
  
}

extension AppDelegate: NameInputPanelDelegate {
  func nameInputPanelDidConfirm(name: String?) {
    startOneTimeTimer(name: name)
  }
  
  func nameInputPanelDidCancel() {
    pendingTimerData = nil
  }
}
