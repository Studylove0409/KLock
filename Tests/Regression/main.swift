import AppKit
import EventKit

var failures = 0

// 不连接系统菜单栏，也能检查 updateStatusIcon 写入的真实按钮标题。
final class TestStatusItem: NSStatusItem {
  private let testButton = NSStatusBarButton(frame: .zero)
  private var testLength: CGFloat = NSStatusItem.variableLength
  override var button: NSStatusBarButton? { testButton }
  override var length: CGFloat {
    get { testLength }
    set { testLength = newValue }
  }
}

final class FakeReminders: ReminderManaging {
  struct Item { var dueDate: Date? }
  var items: [String: Item] = [:]
  var authorization: CheckedContinuation<Bool, Never>?
  var creations = 0
  var onCreate: (() -> Void)?

  func requestAccess() async -> Bool {
    await withCheckedContinuation { authorization = $0 }
  }

  func createReminder(title: String, notes: String?, dueDate: Date?) throws -> String {
    creations += 1
    let id = "reminder-\(creations)"
    items[id] = Item(dueDate: dueDate)
    onCreate?()
    return id
  }

  func updateReminder(withIdentifier identifier: String, dueDate: Date?) throws {
    guard items[identifier] != nil else { throw RemindersError.reminderNotFound }
    items[identifier] = Item(dueDate: dueDate)
  }

  func deleteReminder(withIdentifier identifier: String) async throws {
    items.removeValue(forKey: identifier)
  }

  func grantAccess() {
    let continuation = authorization
    authorization = nil
    continuation?.resume(returning: true)
  }
}

final class FakeAlarmSound: AlarmSoundPlaying {
  var loops = false
  var volume: Float = 0
  var isPlaying = false

  func play() -> Bool { isPlaying = true; return true }
  func stop() -> Bool { isPlaying = false; return true }
}

func pumpMainLoop(until condition: () -> Bool, timeout: TimeInterval = 2) {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  }
}

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
  if condition() {
    print("  ✓ \(label)")
  } else {
    print("  ✗ \(label)")
    failures += 1
  }
}

let delegate = AppDelegate()
let statusItem = TestStatusItem()
delegate.statusItem = statusItem
UserDefaults.standard.set(true, forKey: "showNextTimerInMenuBar")
UserDefaults.standard.set(false, forKey: "useCustomMenuBarSymbol")
UserDefaults.standard.set(false, forKey: "useAlternativeMenuBarIcon")
UserDefaults.standard.set(true, forKey: "useCustomMenuBarIcon")
UserDefaults.standard.set("备用", forKey: "customMenuBarWord")
let now = Date()
delegate.activeTimers = [
  (id: UUID(), name: "暂停", startTime: now, duration: 20,
   reminderId: nil, pausedRemaining: 20, recordId: nil),
  (id: UUID(), name: "运行", startTime: now, duration: 40,
   reminderId: nil, pausedRemaining: nil, recordId: nil),
]
expect(delegate.nextTimerIndexForMenuBar() == 1, "菜单栏忽略剩余时间更短的暂停计时器")
delegate.updateStatusIcon()
let runningTitle = (statusItem.button?.cell as? NSButtonCell)?.title ?? ""
expect(runningTitle.hasPrefix("运行:"), "菜单栏标题显示运行中的计时器")
delegate.activeTimers.removeLast()
expect(delegate.nextTimerIndexForMenuBar() == nil, "全部暂停时不选择下一计时器")
delegate.updateStatusIcon()
let fallbackTitle = (statusItem.button?.cell as? NSButtonCell)?.title ?? ""
expect(fallbackTitle == "备用", "全部暂停时回落到自定义菜单栏文字")
UserDefaults.standard.set(false, forKey: "useCustomMenuBarIcon")
UserDefaults.standard.set(true, forKey: "useAlternativeMenuBarIcon")
delegate.updateStatusIcon()
let iconTitle = (statusItem.button?.cell as? NSButtonCell)?.title ?? ""
expect(iconTitle.isEmpty && statusItem.button?.image != nil, "全部暂停时也能回落到图标")
UserDefaults.standard.set(false, forKey: "useAlternativeMenuBarIcon")

UserDefaults.standard.set(true, forKey: "showNextTimerInMenuBar")
UserDefaults.standard.set(true, forKey: "allowReminders")
UserDefaults.standard.set(false, forKey: "ignoreShortTimers")
UserDefaults.standard.set(true, forKey: "deleteReminders")
let reminders = FakeReminders()
let reminderDelegate = AppDelegate()
reminderDelegate.remindersManager = reminders
let pausedId = UUID()
reminders.items["existing"] = .init(dueDate: now.addingTimeInterval(120))
reminderDelegate.activeTimers = [
  (id: pausedId, name: "测试", startTime: now, duration: 120,
   reminderId: "existing", pausedRemaining: nil, recordId: nil),
]
reminderDelegate.togglePause(id: pausedId)
expect(reminders.items["existing"]?.dueDate == nil, "暂停时移除提醒的到期时间")
reminderDelegate.togglePause(id: pausedId)
let resumedDueDate = reminderDelegate.activeTimers[0].startTime.addingTimeInterval(120)
expect(
  reminders.items["existing"]?.dueDate == resumedDueDate,
  "继续时将提醒更新到新的到期时间")

let pendingReminders = FakeReminders()
let pendingDelegate = AppDelegate()
pendingDelegate.remindersManager = pendingReminders
pendingDelegate.pendingTimerData = (Date(), 120)
pendingDelegate.startOneTimeTimer(name: "删除授权中的计时器")
pumpMainLoop(until: { pendingReminders.authorization != nil })
expect(pendingReminders.authorization != nil, "模拟提醒事项授权等待")
if let timerId = pendingDelegate.activeTimers.first?.id {
  pendingDelegate.deleteTimer(id: timerId)
}
pendingReminders.grantAccess()
pumpMainLoop(until: { pendingReminders.creations > 0 }, timeout: 0.2)
expect(pendingReminders.items.isEmpty, "同步删除开启时授权后不会留下孤立提醒")

let immediatelyDeletedReminders = FakeReminders()
let immediatelyDeletedDelegate = AppDelegate()
immediatelyDeletedDelegate.remindersManager = immediatelyDeletedReminders
immediatelyDeletedDelegate.pendingTimerData = (Date(), 120)
immediatelyDeletedDelegate.startOneTimeTimer(name: "立即删除")
if let timerId = immediatelyDeletedDelegate.activeTimers.first?.id {
  immediatelyDeletedDelegate.deleteTimer(id: timerId)
}
pumpMainLoop(until: { immediatelyDeletedReminders.authorization != nil }, timeout: 0.2)
expect(immediatelyDeletedReminders.authorization == nil, "立即删除后不会再发起提醒事项授权")
immediatelyDeletedReminders.grantAccess()

let racingReminders = FakeReminders()
let racingDelegate = AppDelegate()
racingDelegate.remindersManager = racingReminders
racingDelegate.pendingTimerData = (Date(), 120)
racingDelegate.startOneTimeTimer(name: "创建完成时删除")
pumpMainLoop(until: { racingReminders.authorization != nil })
let racingTimerId = racingDelegate.activeTimers[0].id
racingReminders.onCreate = {
  racingDelegate.deleteTimer(id: racingTimerId)
  UserDefaults.standard.set(false, forKey: "deleteReminders")
}
racingReminders.grantAccess()
pumpMainLoop(until: { racingReminders.creations > 0 && racingReminders.items.isEmpty }, timeout: 0.3)
expect(racingReminders.creations == 1 && racingReminders.items.isEmpty,
       "创建时删除按删除时的设置清理提醒")
UserDefaults.standard.set(true, forKey: "deleteReminders")

let pauseDuringCreateReminders = FakeReminders()
let pauseDuringCreateDelegate = AppDelegate()
pauseDuringCreateDelegate.remindersManager = pauseDuringCreateReminders
pauseDuringCreateDelegate.pendingTimerData = (Date(), 120)
pauseDuringCreateDelegate.startOneTimeTimer(name: "创建时暂停")
pumpMainLoop(until: { pauseDuringCreateReminders.authorization != nil })
let pauseDuringCreateId = pauseDuringCreateDelegate.activeTimers[0].id
pauseDuringCreateReminders.onCreate = {
  pauseDuringCreateDelegate.togglePause(id: pauseDuringCreateId)
}
pauseDuringCreateReminders.grantAccess()
pumpMainLoop(until: { pauseDuringCreateReminders.creations > 0 })
expect(pauseDuringCreateReminders.items["reminder-1"]?.dueDate == nil,
       "创建期间暂停后提醒不保留旧到期时间")

let delayedReminders = FakeReminders()
let delayedDelegate = AppDelegate()
delayedDelegate.remindersManager = delayedReminders
delayedDelegate.pendingTimerData = (Date(), 120)
delayedDelegate.startOneTimeTimer(name: "授权期间暂停")
pumpMainLoop(until: { delayedReminders.authorization != nil })
let delayedTimerId = delayedDelegate.activeTimers[0].id
delayedDelegate.togglePause(id: delayedTimerId)
delayedDelegate.togglePause(id: delayedTimerId)
delayedDelegate.togglePause(id: delayedTimerId)
delayedReminders.grantAccess()
pumpMainLoop(until: { delayedReminders.creations > 0 })
expect(delayedReminders.items["reminder-1"] != nil, "授权后创建暂停中的提醒")
expect(delayedReminders.items["reminder-1"]?.dueDate == nil, "授权期间暂停不会创建旧到期时间")
delayedDelegate.togglePause(id: delayedTimerId)
let delayedDueDate = delayedDelegate.activeTimers[0].startTime.addingTimeInterval(120)
expect(delayedReminders.items["reminder-1"]?.dueDate == delayedDueDate, "授权完成后继续能更新提醒")
UserDefaults.standard.set(true, forKey: "deleteReminders")
delayedDelegate.deleteTimer(id: delayedTimerId)
pumpMainLoop(until: { delayedReminders.items.isEmpty })
expect(delayedReminders.items.isEmpty, "授权完成并关联后删除计时器会删除提醒")

UserDefaults.standard.set(false, forKey: "deleteReminders")
let retainedReminders = FakeReminders()
let retainedDelegate = AppDelegate()
retainedDelegate.remindersManager = retainedReminders
retainedDelegate.pendingTimerData = (Date(), 120)
retainedDelegate.startOneTimeTimer(name: "保留提醒")
pumpMainLoop(until: { retainedReminders.authorization != nil })
if let timerId = retainedDelegate.activeTimers.first?.id {
  retainedDelegate.deleteTimer(id: timerId)
}
retainedReminders.grantAccess()
pumpMainLoop(until: { retainedReminders.creations > 0 })
expect(retainedReminders.items.count == 1, "关闭同步删除时保留授权后创建的提醒")

let eventStore = EKEventStore()
let eventReminder = EKReminder(eventStore: eventStore)
let preciseDueDate = Date(timeIntervalSinceReferenceDate: 800_000_000.2)
let expectedDueDate = Date(timeIntervalSinceReferenceDate: 800_000_001)
RemindersManager.setSchedule(of: eventReminder, dueDate: preciseDueDate)
let eventDueDate = eventReminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
expect(eventDueDate == expectedDueDate, "提醒到期时间保留秒级精度且不提前")
expect(eventReminder.alarms?.first?.absoluteDate == expectedDueDate, "提醒使用与到期时间一致的绝对闹铃")
RemindersManager.setSchedule(of: eventReminder, dueDate: nil)
expect(eventReminder.dueDateComponents == nil, "暂停时清除 EventKit 到期时间")
expect(eventReminder.alarms?.isEmpty ?? true, "暂停时清除 EventKit 闹铃")

var playedSounds: [FakeAlarmSound] = []
let sounds = SoundManager { _, _ in
  let sound = FakeAlarmSound()
  playedSounds.append(sound)
  return sound
}
let firstSoundId = UUID()
let secondSoundId = UUID()
let soundURL = URL(fileURLWithPath: "/unused-test-sound")
sounds.playSound(at: soundURL, for: firstSoundId, loop: true)
sounds.playSound(at: soundURL, for: secondSoundId, loop: true)
expect(playedSounds[0].isPlaying && playedSounds[1].isPlaying, "两个计时器能各自播放闹铃")
sounds.stopSound(for: firstSoundId)
expect(!playedSounds[0].isPlaying && playedSounds[1].isPlaying, "停止前一个闹铃不会停止后一个")
sounds.stopSound(for: UUID())
expect(playedSounds[1].isPlaying, "停止不存在的计时器不会影响播放中的声音")
sounds.playSound(at: soundURL, for: secondSoundId, loop: true)
expect(!playedSounds[1].isPlaying && playedSounds[2].isPlaying, "同一计时器重播只替换自己的声音")
sounds.stopSound(for: secondSoundId)
expect(!playedSounds[2].isPlaying, "停止重播后的声音")

// 从松手到确认使用真实面板与 AppDelegate；等待和取消都不能创建计时器。
_ = NSApplication.shared
UserDefaults.standard.set(false, forKey: "allowReminders")
UserDefaults.standard.set(false, forKey: "allowCustomNames")
func findButton(_ title: String, in view: NSView) -> NSButton? {
  if let button = view as? NSButton,
    button.title == title || button.accessibilityLabel() == title { return button }
  for child in view.subviews {
    if let button = findButton(title, in: child) { return button }
  }
  return nil
}
func visibleButton(_ title: String) -> NSButton? {
  NSApp.windows.lazy.filter { $0.isVisible }.compactMap { window in
    window.contentView.flatMap { findButton(title, in: $0) }
  }.first
}
func editableField(in view: NSView) -> NSTextField? {
  if let field = view as? NSTextField, field.isEditable { return field }
  for child in view.subviews {
    if let field = editableField(in: child) { return field }
  }
  return nil
}
func sendKeyEquivalent(_ characters: String, keyCode: UInt16, to window: NSWindow?) -> Bool {
  guard let window = window,
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
  else { return false }
  return window.performKeyEquivalent(with: event)
}
func findGlass(in view: NSView) -> NSVisualEffectView? {
  if let glass = view as? NSVisualEffectView { return glass }
  for child in view.subviews {
    if let glass = findGlass(in: child) { return glass }
  }
  return nil
}
func descendants(of view: NSView) -> [NSView] {
  [view] + view.subviews.flatMap { descendants(of: $0) }
}
func captureLayout(_ window: NSWindow, name: String) {
  guard let directory = ProcessInfo.processInfo.environment["DROPCLOCK_UI_ARTIFACTS"],
    let content = window.contentView
  else { return }
  content.layoutSubtreeIfNeeded()
  guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
  content.cacheDisplay(in: content.bounds, to: bitmap)
  let url = URL(fileURLWithPath: directory)
  try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  try? bitmap.representation(using: .png, properties: [:])?.write(
    to: url.appendingPathComponent("\(name).png"))
}
func redComponent(_ color: NSColor?, appearance: NSAppearance) -> CGFloat? {
  var result: CGFloat?
  appearance.performAsCurrentDrawingAppearance {
    result = color?.usingColorSpace(.deviceRGB)?.redComponent
  }
  return result
}
let adjustDelegate = AppDelegate()
let releasePoint = NSPoint(x: NSScreen.main?.visibleFrame.midX ?? 0,
                           y: NSScreen.main?.visibleFrame.midY ?? 0)
adjustDelegate.beginDurationAdjustment(duration: 300, at: releasePoint)
expect(adjustDelegate.activeTimers.isEmpty, "松手后只准备时长，不立即开始")
expect(adjustDelegate.pendingTimerData?.duration == 300, "浮条保留松手时长")
if let window = visibleButton("增加 15 秒")?.window,
  let content = window.contentView,
  let chrome = findGlass(in: content),
  let aqua = NSAppearance(named: .aqua), let dark = NSAppearance(named: .darkAqua)
{
  content.layoutSubtreeIfNeeded()
  let buttons = descendants(of: content).compactMap { $0 as? NSButton }
  let steps = buttons.filter { [-60, -15, 15, 60].contains($0.tag) }
  expect((288...300).contains(window.frame.width) && (118...128).contains(window.frame.height),
         "微调面板宽 288–300、高 118–128，容纳独立三层")
  expect(buttons.filter { $0.title == "开始" }.count == 1
         && !buttons.contains { $0.title == "取消" }, "微调仅一颗开始胶囊，取消使用独立 ×")
  expect(steps.count == 4 && steps.allSatisfy {
    abs($0.bounds.height - 26) < 0.1
      && abs($0.bounds.height - Glass.stepChipHeight) < 0.1
      && abs($0.intrinsicContentSize.height - Glass.stepChipHeight) < 0.1
      && abs(($0.layer?.cornerRadius ?? 0) - 13) < 0.1
      && $0.layer?.borderWidth == 0 && $0.font?.pointSize == 11
  }, "四个步进实际与固有高度共用 26pt 令牌，保持 13 圆角、11pt 字、无描边")
  let duration = descendants(of: content).compactMap { $0 as? NSTextField }
    .first { $0.accessibilityLabel() == "当前时长" }
  let traits = duration?.font?.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
  let weight = (traits?[.weight] as? NSNumber)?.doubleValue ?? -1
  expect((32...34).contains(duration?.font?.pointSize ?? 0) && weight >= 0.29,
         "微调时长使用 32–34pt semibold，第一眼先看到时长")
  if let duration = duration, let font = duration.font,
    let start = buttons.first(where: { $0.title == "开始" }),
    let cancel = buttons.first(where: { $0.accessibilityLabel() == "取消" })
  {
    // 用实际布局坐标验证层级，防止重新退回夹住时长的 header 横排。
    func rect(_ view: NSView) -> NSRect {
      let result = view.convert(view.bounds, to: chrome)
      return chrome.isFlipped ? result : NSRect(
        x: result.minX, y: chrome.bounds.height - result.maxY,
        width: result.width, height: result.height)
    }
    let timeRect = rect(duration)
    let startRect = rect(start)
    let cancelRect = rect(cancel)
    let orderedSteps = steps.sorted { rect($0).minX < rect($1).minX }
    expect(abs(timeRect.midX - chrome.bounds.midX) < 0.1
           && duration.superview === chrome && cancel.superview === chrome
           && (24...28).contains(cancelRect.width) && cancelRect.width == cancelRect.height
           && cancelRect.minX <= 12 && cancelRect.minY <= 12
           && cancel.layer?.borderWidth == 0
           && (cancel.layer?.backgroundColor?.alpha ?? 1) == 0,
           "时长独占一行居中，× 独立定位左上且无描边重底")
    let digitWidths = (0...9).map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
    expect((digitWidths.max() ?? 0) - (digitWidths.min() ?? 0) < 0.1,
           "时长采用等宽数字，步进时不抖动")
    expect((120...140).contains(startRect.width) && abs(startRect.height - 36) < 0.1
           && abs(startRect.midX - chrome.bounds.midX) < 0.1
           && startRect.minY > timeRect.maxY && startRect.midY > chrome.bounds.midY
           && abs((start.layer?.cornerRadius ?? 0) - startRect.height / 2) < 0.1
           && start.font?.pointSize == 13 && font.pointSize > 2 * (start.font?.pointSize ?? 0),
           "开始为独立底层 120–140×36 胶囊，垂直偏下居中")
    expect(orderedSteps.map(\.title) == ["−1分", "−15秒", "+15秒", "+1分"]
           && orderedSteps.allSatisfy {
             rect($0).minY >= timeRect.maxY + 8
           }, "时长、轻步进、开始分成三层，互不重叠")
    // 8pt 目标允许 ±2pt 布局余量，底部仍须保留至少 4pt。
    let startGaps = orderedSteps.map { startRect.minY - rect($0).maxY }
    expect(startGaps.count == 4 && startGaps.allSatisfy { (6...10).contains($0) },
           "步进至开始保持 8±2pt 竖向间距")
    expect(chrome.bounds.maxY - startRect.maxY >= 3.9,
           "开始胶囊底部至少留 4pt，不挤出面板")
    if let first = orderedSteps.first, let last = orderedSteps.last {
      let gaps = zip(orderedSteps, orderedSteps.dropFirst()).map { rect($1).minX - rect($0).maxX }
      let widths = orderedSteps.map { rect($0).width }
      expect(gaps.allSatisfy { abs($0 - 8) < 0.1 }
             && (widths.max() ?? 0) - (widths.min() ?? 0) > 1
             && rect(first).minX >= 24 && chrome.bounds.maxX - rect(last).maxX >= 24
             && abs((rect(first).minX + rect(last).maxX) / 2 - chrome.bounds.midX) < 0.1,
             "步进使用固有宽度和 8pt 间距居中，两侧留白、不等宽撑满")
    }
    expect(([duration, start, cancel] + steps).allSatisfy { chrome.bounds.contains(rect($0)) },
           "三层内容及关闭按钮完整位于面板内")
    for appearance in [aqua, dark] {
      window.appearance = appearance
      content.layoutSubtreeIfNeeded()
      expect(steps.allSatisfy {
        (0.06...0.08).contains($0.layer?.backgroundColor?.alpha ?? 1)
          && $0.layer?.borderWidth == 0
      } && (0.35...0.50).contains(start.layer?.backgroundColor?.alpha ?? 1),
             "\(appearance.name.rawValue) 步进低对比、开始使用半透明强调色")
      expect(steps.allSatisfy {
        let color = $0.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let expected: NSColor = $0.tag < 0 ? .secondaryLabelColor : .labelColor
        var matches = false
        appearance.performAsCurrentDrawingAppearance {
          matches = color?.usingColorSpace(.deviceRGB) == expected.usingColorSpace(.deviceRGB)
        }
        return matches
      }, "\(appearance.name.rawValue) 减少侧次要、增加侧主文字色")
      captureLayout(window, name: "duration-adjust-\(appearance.name.rawValue)")
    }
  } else {
    expect(false, "微调三层内容及独立关闭按钮齐全")
  }
  expect(chrome.material == Glass.panelMaterial && chrome.layer?.cornerRadius == Glass.panelRadius,
         "浮条使用统一面板材质和圆角")
  expect(!window.isOpaque && window.backgroundColor.alphaComponent == 0
         && chrome.material == .hudWindow && chrome.blendingMode == .behindWindow
         && chrome.state == .active && (chrome.layer?.cornerRadius ?? 0) >= 20
         && chrome.layer?.cornerCurve == .continuous
         && (chrome.layer?.borderWidth ?? 2) <= 1,
         "微调使用实时透壁纸 HUD 玻璃、连续圆角和 hairline 外边框")
  window.appearance = aqua
  let lightBorder = chrome.layer?.borderColor.flatMap(NSColor.init(cgColor:))
  window.appearance = dark
  let darkBorder = chrome.layer?.borderColor.flatMap(NSColor.init(cgColor:))
  expect((redComponent(lightBorder, appearance: aqua) ?? 1) < 0.2
         && (redComponent(darkBorder, appearance: dark) ?? 0) > 0.8
         && (lightBorder?.alphaComponent ?? 1) <= 0.10
         && (darkBorder?.alphaComponent ?? 1) <= 0.10,
         "浮条描边随浅色和深色外观变化")
  captureLayout(window, name: "duration-adjust")
} else {
  expect(false, "浮条使用统一面板材质和圆角")
  expect(false, "浮条描边随浅色和深色外观变化")
}
expect(sendKeyEquivalent("\u{1b}", keyCode: 53, to: visibleButton("取消")?.window),
       "浮条支持 Escape 取消")
expect(adjustDelegate.pendingTimerData == nil && adjustDelegate.activeTimers.isEmpty,
       "取消浮条丢弃待创建计时器")
adjustDelegate.beginDurationAdjustment(duration: 300, at: releasePoint)
visibleButton("+15秒")?.performClick(nil)
expect(sendKeyEquivalent("\r", keyCode: 36, to: visibleButton("开始")?.window),
       "浮条支持 Return 确认")
expect(adjustDelegate.activeTimers.first?.duration == 315,
       "未开启自定义名称时使用微调后的时长开始")
expect(adjustDelegate.pendingTimerData == nil, "开始后清理待创建数据")
adjustDelegate.beginDurationAdjustment(duration: 3, at: releasePoint)
visibleButton("−1分")?.performClick(nil)
visibleButton("−15秒")?.performClick(nil)
visibleButton("+1分")?.performClick(nil)
visibleButton("+15秒")?.performClick(nil)
visibleButton("开始")?.performClick(nil)
expect(adjustDelegate.activeTimers.last?.duration == 76,
       "浮条四个步进按钮可用且减少时不低于 1 秒")

UserDefaults.standard.set(true, forKey: "allowCustomNames")
let namingDelegate = AppDelegate()
namingDelegate.beginDurationAdjustment(duration: 300, at: releasePoint)
visibleButton("−15秒")?.performClick(nil)
visibleButton("开始")?.performClick(nil)
expect(namingDelegate.activeTimers.isEmpty && namingDelegate.pendingTimerData?.duration == 285,
       "开启自定义名称时先进入命名，保留微调时长")
if let window = visibleButton("开始")?.window, let content = window.contentView,
  let field = editableField(in: content), let button = visibleButton("开始"),
  let aqua = NSAppearance(named: .aqua), let dark = NSAppearance(named: .darkAqua)
{
  window.appearance = aqua
  let light = redComponent(field.textColor, appearance: field.effectiveAppearance)
  window.appearance = dark
  let darkValue = redComponent(field.textColor, appearance: field.effectiveAppearance)
  expect((light ?? 1) < 0.3 && (darkValue ?? 0) > 0.7, "命名输入文字跟随浅色和深色外观")
  content.layoutSubtreeIfNeeded()
  let views = descendants(of: content)
  let buttons = views.compactMap { $0 as? NSButton }
  let chip = views.compactMap { $0 as? NSTextField }
    .first { $0.accessibilityLabel() == "拟用时长" }
  expect((280...420).contains(window.frame.width) && (36...44).contains(window.frame.height),
         "命名改为宽 280–420、高 36–44 的横条")
  expect(!buttons.contains { $0.title == "取消" || $0.title == "开始" }
         && buttons.contains { $0.accessibilityLabel() == "取消" }
         && buttons.contains { $0.accessibilityLabel() == "开始" },
         "命名没有底栏双宽钮，提供独立 × 和小确认")
  expect(chip?.stringValue == "04:45" && !field.isBezeled && !field.isBordered,
         "命名芯片展示实际微调时长，输入无边框")
  let glasses = views.compactMap { $0 as? NSVisualEffectView }
  expect(glasses.count == 2 && glasses.allSatisfy {
    $0.blendingMode == .behindWindow && $0.state == .active
      && abs(($0.layer?.cornerRadius ?? 0) - $0.bounds.height / 2) < 0.1
  }, "命名主胶囊与独立取消圆均使用实时玻璃")
  expect(!button.isBordered && button.bounds.height <= 34,
         "命名确认使用横条右侧小按钮")
  captureLayout(window, name: "name-input")
} else {
  expect(false, "命名输入文字跟随浅色和深色外观")
  expect(false, "命名横条及玻璃芯片可见")
}
expect(sendKeyEquivalent("\u{1b}", keyCode: 53, to: visibleButton("取消")?.window),
       "命名面板支持 Escape 取消")
expect(namingDelegate.pendingTimerData == nil && namingDelegate.activeTimers.isEmpty,
       "取消命名后不启动计时器")
namingDelegate.beginDurationAdjustment(duration: 300, at: releasePoint)
visibleButton("−15秒")?.performClick(nil)
visibleButton("开始")?.performClick(nil)
if let content = visibleButton("开始")?.window?.contentView {
  editableField(in: content)?.stringValue = "测试命名"
}
expect(sendKeyEquivalent("\r", keyCode: 36, to: visibleButton("开始")?.window),
       "命名面板支持 Return 确认")
expect(namingDelegate.activeTimers.first?.duration == 285
       && namingDelegate.activeTimers.first?.name == "测试命名",
       "确认命名后以微调时长启动计时器")
namingDelegate.beginDurationAdjustment(duration: 60, at: releasePoint)
visibleButton("开始")?.performClick(nil)
if let content = visibleButton("开始")?.window?.contentView, let field = editableField(in: content) {
  field.stringValue = "输入框回车"
  expect(field.delegate?.control?(field, textView: NSTextView(),
         doCommandBy: #selector(NSResponder.insertNewline(_:))) == true,
         "命名输入框内 Return 直接开始")
}
expect(namingDelegate.activeTimers.last?.name == "输入框回车"
       && namingDelegate.activeTimers.last?.duration == 60, "输入框 Return 保留名称与时长")
UserDefaults.standard.set(false, forKey: "allowCustomNames")

// 可选视图快照只用于布局目视，不把 NSHostingView 缓存图当作系统玻璃或 AX 证明。
if ProcessInfo.processInfo.environment["DROPCLOCK_UI_ARTIFACTS"] != nil {
  let alertPanel = ReminderAlertPanel()
  alertPanel.show(
    timerName: "Call Alex", detail: "计时结束",
    onClose: {}, onTimeout: {}, onSnooze: { _ in }, onPause: {}, onDelete: {})
  let alertReadyAt = Date().addingTimeInterval(0.35)
  pumpMainLoop(until: { Date() >= alertReadyAt })
  if let window = NSApp.windows.first(where: {
    $0.isVisible && $0.level == .screenSaver && !$0.ignoresMouseEvents
  }) {
    captureLayout(window, name: "reminder")
  }
  alertPanel.close()
}

// 覆盖真实手势处理器的松手和取消分支，不依赖屏幕上的鼠标输入。
final class TestPanGesture: NSPanGestureRecognizer {
  var testState: NSGestureRecognizer.State = .possible
  var testTranslation = NSPoint.zero
  override var state: NSGestureRecognizer.State {
    get { testState }
    set { testState = newValue }
  }
  override func translation(in view: NSView?) -> NSPoint { testTranslation }
}
UserDefaults.standard.set(false, forKey: "showDragIndicator")
let dragDelegate = AppDelegate()
let gesture = TestPanGesture()
gesture.testState = .began
dragDelegate.handleDrag(gesture)
gesture.testTranslation = NSPoint(x: 118.5, y: 0)
gesture.testState = .changed
dragDelegate.handleDrag(gesture)
expect(dragDelegate.dragTimeInterval == 300, "真实普通拖拽按拖距吸附到 5 分钟")
gesture.testState = .ended
dragDelegate.handleDrag(gesture)
expect(dragDelegate.activeTimers.isEmpty && dragDelegate.pendingTimerData?.duration == 300,
       "真实松手进入浮条且没有启动")
visibleButton("取消")?.performClick(nil)
gesture.testTranslation = .zero
gesture.testState = .began
dragDelegate.handleDrag(gesture)
gesture.testTranslation = NSPoint(x: 118.5, y: 0)
gesture.testState = .changed
dragDelegate.handleDrag(gesture)
gesture.testState = .cancelled
dragDelegate.handleDrag(gesture)
expect(dragDelegate.activeTimers.isEmpty && dragDelegate.pendingTimerData == nil,
       "系统取消拖拽时不打开浮条或启动计时器")

let visible = NSRect(x: -1440, y: 25, width: 1440, height: 855)
let panelSize = NSSize(width: 326, height: 150)
let proposed = NSPoint(x: visible.maxX - panelSize.width / 2, y: visible.minY - panelSize.height)
let clamped = Glass.clampedPanelOrigin(proposed, size: panelSize, visibleFrame: visible)
expect(visible.insetBy(dx: 8, dy: 8).contains(NSRect(origin: clamped, size: panelSize)),
       "浮条在负坐标屏幕角落保持在可见区域")

// 从真实历史窗口行触发回调，确认使用记录的名称和完整时长。
let historyDelegate = AppDelegate()
let historyName = "历史再计一次回归"
_ = HistoryStore.shared.recordCreated(name: historyName, duration: 1234)
historyDelegate.showHistory()
if let content = HistoryWindowController.shared.window?.contentView,
  let rerun = findButton("再计一次", in: content)
{
  rerun.performClick(nil)
  expect(historyDelegate.activeTimers.last?.name == historyName
         && historyDelegate.activeTimers.last?.duration == 1234,
         "历史行再计一次按记录名称和时长启动")
} else {
  expect(false, "历史行再计一次按钮可见")
}
HistoryWindowController.shared.window?.close()

if failures == 0 {
  print("回归测试全部通过")
  exit(0)
} else {
  print("回归测试失败 \(failures) 项")
  exit(1)
}
