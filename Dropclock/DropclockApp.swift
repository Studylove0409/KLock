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
        let now = Date()
        
        let endTime = savedTimer.startTime.addingTimeInterval(
          savedTimer.duration)
        let remainingTime = endTime.timeIntervalSince(now)
        
        if remainingTime > 0 {
          let timerObj = Timer.scheduledTimer(
            withTimeInterval: remainingTime, repeats: false
          ) { [weak self] _ in
            self?.timerFinished(id: timerId)
          }
          
          activeTimers.append(
            (
              id: timerId,
              name: savedTimer.name,
              startTime: savedTimer.startTime,
              duration: savedTimer.duration,
              timer: timerObj,
              reminderId: savedTimer.reminderId
            ))
        } else {
          let timerObj = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: false
          ) { [weak self] _ in
            self?.timerFinished(id: timerId)
          }
          
          activeTimers.append(
            (
              id: timerId,
              name: savedTimer.name,
              startTime: savedTimer.startTime,
              duration: savedTimer.duration,
              timer: timerObj,
              reminderId: savedTimer.reminderId
            ))
          
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

  private func textWidth(_ text: String) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium)
    ]
    return NSAttributedString(string: text, attributes: attributes).size().width
  }

  /// 按渲染宽度截断：原来按字符数算，中文一个字约占两个英文宽度，会撑爆菜单栏。
  private func truncatedName(_ name: String, maxWidth: CGFloat) -> String {
    guard textWidth(name) > maxWidth else { return name }
    let ellipsis = "…"
    var kept = name
    while !kept.isEmpty {
      kept.removeLast()
      let candidate = kept + ellipsis
      if textWidth(candidate) <= maxWidth { return candidate }
    }
    return ellipsis
  }

  internal func updateStatusIcon() {
    if UserDefaults.standard.bool(forKey: "showNextTimerInMenuBar") && activeTimers.count > 0 {
      
      let nextTimer = activeTimers.min { timer1, timer2 in
        let endTime1 = timer1.startTime.addingTimeInterval(timer1.duration)
        let endTime2 = timer2.startTime.addingTimeInterval(timer2.duration)
        return endTime1 < endTime2
      }
      
      if let timer = nextTimer {
        let now = Date()
        let endTime = timer.startTime.addingTimeInterval(timer.duration)
        let remainingTime = endTime.timeIntervalSince(now)
        
        if remainingTime > 0 {
          let formattedTime = formatTimeInterval(remainingTime)
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
      if activeTimers.count > 0 {
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
          
          let text = activeTimers.count > 9 ? "+" : "\(activeTimers.count)"
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
  
  internal func startOneTimeTimer(name: String?) {
    if let timerData = pendingTimerData
        ?? (dragTimeInterval > 0 ? (Date(), dragTimeInterval) : nil)
    {
      let timerId = UUID()
      let reminderId: String? = nil
      
      let timerObj = Timer.scheduledTimer(
        withTimeInterval: timerData.duration, repeats: false
      ) { [weak self] _ in
        self?.timerFinished(id: timerId)
      }
      
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
          startTime: timerData.startTime,
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
  private func showReminderError(_ error: Error) {
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
      alert.messageText = "无法创建提醒事项"
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
      NotificationManager.shared.dispatchNotification(timerName: timerName)
      let defaults = UserDefaults.standard
      let shouldLoopAlarm = defaults.bool(forKey: "playAlarmSound")
        && defaults.bool(forKey: "loopAlarmUntilStopped")
      SoundManager.shared.playSelectedAlarmIfEnabled(loop: shouldLoopAlarm)

      if shouldLoopAlarm {
        // Keep the finished timer in the list so the user can stop the alarm by deleting it. 
        // Dunno how I would do it otherwise. TODO: Improve!
      } else {
        activeTimers.remove(at: index)
      }
    }

    updateStatusIcon()
    updateMenu()
    saveTimers()
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
          }
        }
      }
    }
    
    timerToRemove.timer.invalidate()
    activeTimers.remove(at: timerIndex)
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
      return "\(timer.id.uuidString)#\(Int(max(0, remaining)))#\(timer.name ?? "")"
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
        let formattedTime = formatTimeInterval(remainingTime)
        
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
  
  private func formatTimeInterval(_ timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(max(0, timeInterval))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
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
