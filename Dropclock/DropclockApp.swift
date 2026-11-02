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
  internal var dragTimeInterval: TimeInterval = 0
  internal var dragStartLocation: CGPoint?
  internal var dragLineView: DragLineView?
  internal var dragLineWindow: NSWindow?
  internal let MinuteThreshold: CGFloat = 130
  internal let ThirtySecondThreshold: CGFloat = 80
  internal let SecondThreshold: CGFloat = 50

  private var statusIconUpdateTimer: Timer?
  /// 所有计时器共用一个每秒 tick，避免 N 个计时器开 N 个 Timer。
  private var tickTimer: Timer?
  /// 循环闹铃时已结束、但需要留在列表里等用户手动停止的计时器。
  private var finishedTimerIds: Set<UUID> = []
  /// 屏幕中央的强提醒卡片；同一时刻只显示一个，其余排队。
  private var reminderAlertPanel: ReminderAlertPanel?
  private var reminderAlertTimerId: UUID?
  private var pendingAlerts:
  [(id: UUID, name: String?, duration: TimeInterval)] = []
  internal var activeTimers:
  [(
    id: UUID, name: String?, startTime: Date, duration: TimeInterval,
    reminderId: String?, pausedRemaining: TimeInterval?, recordId: UUID?
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
        reminderId: timer.reminderId,
        isFinished: finishedTimerIds.contains(timer.id),
        pausedRemaining: timer.pausedRemaining,
        recordId: timer.recordId?.uuidString
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

        activeTimers.append(
          (
            id: timerId,
            name: savedTimer.name,
            startTime: savedTimer.startTime,
            duration: savedTimer.duration,
            reminderId: savedTimer.reminderId,
            pausedRemaining: savedTimer.pausedRemaining,
            recordId: savedTimer.recordId.flatMap { UUID(uuidString: $0) }
          ))

        // 已结束的条目（等用户手动停止循环闹铃）只恢复状态，
        // 不再重新触发一次提醒，否则每次启动都会重复弹窗响铃。
        if savedTimer.isFinished == true {
          finishedTimerIds.insert(timerId)
        }
      }

      refreshTickTimer()
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
    // 不做身份比对：菜单在打开期间可能被替换过，用旧对象比会漏掉关闭事件，
    // 导致 isMenuOpen 一直为 true。
    isMenuOpen = false
    stopMenuRefreshTimer()
    // 打开期间状态栏被冻结，这里补一次，把它和实际剩余时间对齐。
    updateStatusIcon()
  }
  
  private var menuRefreshTimer: Timer?
  
  private func startMenuRefreshTimer() {
    stopMenuRefreshTimer()
    // 必须加到 common 模式：菜单打开时 run loop 处于 eventTracking 模式，
    // 默认模式的定时器完全不会触发，行内数字就会停在打开那一刻。
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self = self, self.isMenuOpen else { return }
      self.refreshOpenMenuRows()
    }
    RunLoop.main.add(timer, forMode: .common)
    menuRefreshTimer = timer
  }

  /// 菜单打开时只刷新每一行的文字，不重建菜单。
  private func refreshOpenMenuRows() {
    let ids = Set(activeTimers.map { $0.id })
    guard ids == Set(rowViews.keys) else {
      // 条目增减了，重建一次；屏幕上这份要等下次打开才会变
      updateMenu()
      return
    }

    for (timerId, view) in rowViews {
      let row = menuRowText(for: timerId)
      view.setContent(text: row.text, isPaused: row.isPaused)
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

  /// 状态栏文字统一用等宽数字：比例字体里「1」比「8」窄，
  /// 每秒刷新会让状态项宽度来回变，菜单栏本身就在抖。
  private static let statusTextFont = NSFont.monospacedDigitSystemFont(
    ofSize: 13, weight: .medium)

  /// 写入状态栏文字。相同内容不重复赋值，避免无谓的重排。
  private func setStatusTitle(_ text: String) {
    guard let button = statusItem?.button else { return }
    if button.font != Self.statusTextFont {
      button.font = Self.statusTextFont
    }
    if button.title != text {
      button.title = text
    }
  }

  internal func updateStatusIcon() {
    // 菜单正开着的时候，绝不碰状态栏。
    // 实测：菜单打开期间只要重设标题（哪怕文字宽度完全相同），AppKit 就会重新
    // 布局状态项，锚在它下面的整份菜单跟着平移 1~2pt，看起来就是左右晃动。
    // 关闭时 menuWillClose 会补一次刷新，所以这里直接返回不会导致时间停住。
    if isMenuOpen { return }

    if UserDefaults.standard.bool(forKey: "showNextTimerInMenuBar")
      && runningTimerCount > 0
    {

      let nextTimer = activeTimers
        .filter { !finishedTimerIds.contains($0.id) }
        .min { timer1, timer2 in
          remainingSeconds(
            startTime: timer1.startTime, duration: timer1.duration,
            pausedRemaining: timer1.pausedRemaining)
            < remainingSeconds(
              startTime: timer2.startTime, duration: timer2.duration,
              pausedRemaining: timer2.pausedRemaining)
        }
      
      if let timer = nextTimer {
        let remainingTime = remainingSeconds(
          startTime: timer.startTime, duration: timer.duration,
          pausedRemaining: timer.pausedRemaining)
        
        if remainingTime > 0 {
          let formattedTime = TimerTextFormatter.duration(remainingTime)
          let displayName = truncatedName(
            timer.name ?? "计时器", maxWidth: Self.menuBarNameWidth)
          let displayText = "\(displayName): \(formattedTime)"
          
          statusItem?.button?.image = nil
          setStatusTitle(displayText)
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
      setStatusTitle(UserDefaults.standard.string(forKey: "customMenuBarWord") ?? "")
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
        self?.updateStatusIcon()
      }
    } else {
      statusIconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.updateStatusIcon()
      }
    }
  }
  
  /// 所有计时器共用一个每秒 tick；没有正在跑的计时器时自动停掉，避免空转。
  private func refreshTickTimer() {
    let hasRunning = activeTimers.contains {
      !finishedTimerIds.contains($0.id)
    }
    if hasRunning {
      guard tickTimer == nil else { return }
      tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
        [weak self] _ in
        self?.checkExpiredTimers()
      }
    } else {
      tickTimer?.invalidate()
      tickTimer = nil
    }
  }

  /// 剩余秒数（暂停时返回冻结值）。
  private func remainingSeconds(
    startTime: Date, duration: TimeInterval, pausedRemaining: TimeInterval?
  ) -> TimeInterval {
    TimerMath.remaining(
      startTime: startTime, duration: duration,
      pausedRemaining: pausedRemaining, now: Date())
  }

  /// 菜单里某一行的显示文本 + 是否暂停，供首次构建和原地更新共用。
  private func menuRowText(for timerId: UUID) -> (text: String, isPaused: Bool) {
    guard let index = activeTimers.firstIndex(where: { $0.id == timerId })
    else { return ("", false) }

    let timer = activeTimers[index]
    let isFinished = finishedTimerIds.contains(timer.id)
    let isPaused = timer.pausedRemaining != nil
    let remaining = remainingSeconds(
      startTime: timer.startTime, duration: timer.duration,
      pausedRemaining: timer.pausedRemaining)

    let formatted: String
    if isFinished {
      formatted = "已结束"
    } else {
      // 不追加「暂停」字样：文字长度一变行宽就变，菜单会左右跳。
      // 暂停状态用文字变灰 + 图标切换来表达。
      formatted = TimerTextFormatter.duration(remaining)
    }

    let name = timer.name ?? "计时器 \(index + 1)"
    return ("\(name): \(formatted)", isPaused)
  }

  private func checkExpiredTimers() {
    let now = Date()
    let expired = activeTimers.filter { timer in
      guard !finishedTimerIds.contains(timer.id),
        timer.pausedRemaining == nil
      else { return false }
      return now >= timer.startTime.addingTimeInterval(timer.duration)
    }
    for timer in expired {
      timerFinished(id: timer.id)
    }
    refreshTickTimer()
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
      
      let recordId = HistoryStore.shared.recordCreated(
        name: name ?? "计时器", duration: timerData.duration, at: startTime)

      activeTimers.append(
        (
          id: timerId,
          name: name,
          startTime: startTime,
          duration: timerData.duration,
          reminderId: reminderId,
          pausedRemaining: nil,
          recordId: recordId
        ))
      
      refreshTickTimer()
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
    guard let index = activeTimers.firstIndex(where: { $0.id == id }) else {
      return
    }

    let timer = activeTimers[index]
    let timerName = timer.name
    NotificationManager.shared.dispatchNotification(timerName: timerName)

    let defaults = UserDefaults.standard
    let shouldLoopAlarm = defaults.bool(forKey: "playAlarmSound")
      && defaults.bool(forKey: "loopAlarmUntilStopped")
    SoundManager.shared.playSelectedAlarmIfEnabled(loop: shouldLoopAlarm)

    if let recordId = timer.recordId {
      HistoryStore.shared.markFinished(recordId: recordId)
    }

    if shouldLoopAlarm {
      // 循环闹铃时保留在列表里并标记为已结束，用户点「删除」即可停止。
      finishedTimerIds.insert(id)
    } else {
      activeTimers.remove(at: index)
    }

    enqueueReminderAlert(
      timerId: id, name: timerName, duration: timer.duration)

    refreshTickTimer()
    updateStatusIcon()
    updateMenu()
    saveTimers()
  }
  
  // MARK: - 结束提醒

  /// 多个计时器同时结束时排队逐个展示，避免后一个卡片顶掉前一个。
  private func enqueueReminderAlert(
    timerId: UUID, name: String?, duration: TimeInterval
  ) {
    pendingAlerts.append((id: timerId, name: name, duration: duration))
    if reminderAlertPanel == nil {
      showNextReminderAlert()
    }
  }

  private func showNextReminderAlert() {
    guard let next = pendingAlerts.first else { return }
    pendingAlerts.removeFirst()

    let minutes = Int(next.duration / 60)
    let detail =
      next.duration < 60
      ? "\(Int(next.duration)) 秒的计时已结束"
      : "\(minutes) 分钟的计时已结束"

    let panel = ReminderAlertPanel()
    reminderAlertPanel = panel
    reminderAlertTimerId = next.id

    panel.show(
      timerName: next.name ?? "计时器",
      detail: detail,
      onClose: { [weak self] in
        self?.dismissReminderAlert(
          timerId: next.id, name: next.name, snoozeMinutes: nil)
      },
      onSnooze: { [weak self] snoozeMinutes in
        self?.dismissReminderAlert(
          timerId: next.id, name: next.name, snoozeMinutes: snoozeMinutes)
      })
  }

  private func dismissReminderAlert(
    timerId: UUID, name: String?, snoozeMinutes: Int?
  ) {
    reminderAlertPanel = nil
    reminderAlertTimerId = nil
    SoundManager.shared.stopActiveSound()
    removeTimerEntry(id: timerId)

    if let snoozeMinutes = snoozeMinutes {
      pendingTimerData = (
        Date(), TimeInterval(snoozeMinutes) * 60
      )
      startOneTimeTimer(name: name)
    }

    showNextReminderAlert()
  }

  /// 从列表里彻底移除某个计时器（含已结束仍残留的条目）。
  private func removeTimerEntry(id: UUID) {
    guard let index = activeTimers.firstIndex(where: { $0.id == id })
    else { return }
    activeTimers.remove(at: index)
    finishedTimerIds.remove(id)
    saveTimers()
    updateStatusIcon()
    updateMenu()
  }

  func deleteTimer(id timerId: UUID) {
    // 按 UUID 定位，避免菜单重建期间计时器列表变动导致删错行。
    guard let timerIndex = activeTimers.firstIndex(where: { $0.id == timerId })
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
    
    finishedTimerIds.remove(timerId)
    if let recordId = timerToRemove.recordId {
      HistoryStore.shared.markCancelled(recordId: recordId)
    }
    activeTimers.remove(at: timerIndex)
    refreshTickTimer()

    // 如果屏幕上的提醒卡片正属于这个计时器，一并关掉并接着显示下一条。
    if reminderAlertTimerId == timerId {
      reminderAlertPanel?.close()
      reminderAlertPanel = nil
      reminderAlertTimerId = nil
      showNextReminderAlert()
    }

    SoundManager.shared.stopActiveSound()
    saveTimers()
    updateStatusIcon()

    updateMenu()
  }
  
  @objc func preferences() {
    PreferencesWindowController.shared.showWindow()
  }

  /// 暂停 / 继续某个计时器。
  func togglePause(id timerId: UUID) {
    guard let index = activeTimers.firstIndex(where: { $0.id == timerId })
    else { return }

    let timer = activeTimers[index]
    // 已结束的条目不允许再切换（它只是在等用户清理）
    guard !finishedTimerIds.contains(timerId) else { return }

    if let frozen = timer.pausedRemaining {
      // 继续：把 startTime 往前挪，使剩余时间正好等于冻结值
      let newStart = TimerMath.resumedStartTime(
        duration: timer.duration, remaining: frozen, now: Date())
      activeTimers[index].startTime = newStart
      activeTimers[index].pausedRemaining = nil
    } else {
      let remaining = remainingSeconds(
        startTime: timer.startTime, duration: timer.duration,
        pausedRemaining: nil)
      activeTimers[index].pausedRemaining = max(0, remaining)
    }

    refreshTickTimer()
    saveTimers()
    updateStatusIcon()
    // 菜单开着的时候不重建，交给原地更新和打开期间的每秒刷新，
    // 否则替换 statusItem.menu 会让菜单「啪」地消失。
    if !isMenuOpen {
      updateMenu()
    }
  }

  @objc func showHistory() {
    HistoryWindowController.shared.showWindow()
  }
  
  @objc func quit() {
    NSApplication.shared.terminate(nil)
  }
  
  private var lastMenuSignature: String?
  /// 当前菜单里每一行对应的视图，用于菜单打开期间原地刷新文字
  private var rowViews: [UUID: HoverView] = [:]

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
    rowViews.removeAll()
    
    if activeTimers.count > 0 {
      menu.addItem(
        NSMenuItem(title: "进行中的计时器", action: nil, keyEquivalent: ""))
      
      for timerInfo in activeTimers {
        let row = menuRowText(for: timerInfo.id)
        let timerId = timerInfo.id
        let menuItem = NSMenuItem()

        let customView = HoverView(
          text: row.text,
          isPaused: row.isPaused,
          frame: NSRect(
            x: 0, y: 0, width: HoverView.rowWidth,
            height: HoverView.rowHeight),
          onTogglePause: { [weak self] in
            guard let self = self else { return ("", false) }
            self.togglePause(id: timerId)
            return self.menuRowText(for: timerId)
          },
          onDelete: { [weak self] in
            self?.deleteTimer(id: timerId)
          }
        )
        menuItem.view = customView
        rowViews[timerId] = customView

        menu.addItem(menuItem)
      }
      
      menu.addItem(NSMenuItem.separator())
    }
    
    menu.addItem(
      NSMenuItem(
        title: "历史记录…", action: #selector(showHistory), keyEquivalent: "h"))
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
