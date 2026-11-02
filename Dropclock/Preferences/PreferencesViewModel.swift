import Combine
import EventKit
import ServiceManagement
import SwiftUI

class PreferencesViewModel: ObservableObject {
  @Published var reminderLists: [EKCalendar] = []
  @Published var selectedList: EKCalendar?
  @Published var allowReminders: Bool = false
  @Published var deleteReminders: Bool = true
  @Published var allowCustomNames: Bool = false
  @Published var startAtLogin: Bool = false
  @Published var ignoreShortTimers: Bool = false
  @Published var allowSecondsMode: Bool = false
  @Published var allowFiveMinuteMode: Bool = true
  @Published var shortTimerThresholdMinutes: Double = 1
  @Published var viewAsMinutes: Bool = false
  @Published var showDragIndicator: Bool = true
  @Published var changeRubberbandColor: Bool = false
  @Published var customMenuBarWord: String = ""
  @Published var useCustomMenuBarIcon: Bool = false {
    didSet {
      if useCustomMenuBarIcon {
        if useAlternativeMenuBarIcon {
          useAlternativeMenuBarIcon = false
        }
        if useCustomMenuBarSymbol {
          useCustomMenuBarSymbol = false
        }
      }
    }
  }
  @Published var customMenuBarSymbol: String = ""
  @Published var useCustomMenuBarSymbol: Bool = false {
    didSet {
      if useCustomMenuBarSymbol {
        if useAlternativeMenuBarIcon {
          useAlternativeMenuBarIcon = false
        }
        if useCustomMenuBarIcon {
          useCustomMenuBarIcon = false
        }
      }
    }
  }
  @Published var useAlternativeMenuBarIcon: Bool = false {
    didSet {
      if useAlternativeMenuBarIcon {
        if useCustomMenuBarIcon {
          useCustomMenuBarIcon = false
        }
        if useCustomMenuBarSymbol {
          useCustomMenuBarSymbol = false
        }
      }
    }
  }
  @Published var dragLineColor: Color = Color.white {
    didSet {
      saveDragLineColor()
    }
  }
  @Published var showNextTimerInMenuBar: Bool = false
  @Published var playAlarmSound: Bool = false
  @Published var selectedAlarmSound: String = ""
  @Published var availableAlarmSounds: [String] = []
  @Published var loopAlarmUntilStopped: Bool = false
  @Published var useCustomAlarmSound: Bool = false
  @Published var customAlarmSoundName: String = ""

  /// 文本输入的延迟保存任务
  private var pendingTextSave: AnyCancellable?

  private struct Keys {
    static let allowReminders = "allowReminders"
    static let deleteReminders = "deleteReminders"
    static let allowCustomNames = "allowCustomNames"
    static let allowSecondsMode = "allowSecondsMode"
    static let allowFiveMinuteMode = "allowFiveMinuteMode"
    static let ignoreShortTimers = "ignoreShortTimers"
    static let shortTimerThresholdMinutes = "shortTimerThresholdMinutes"
    static let viewAsMinutes = "viewAsMinutes"
    static let showDragIndicator = "showDragIndicator"
    static let changeRubberbandColor = "changeRubberbandColor"
    static let dragLineColor = "dragLineColor"
    static let useCustomMenuBarSymbol = "useCustomMenuBarSymbol"
    static let customMenuBarSymbol = "customMenuBarSymbol"
    static let useCustomMenuBarIcon = "useCustomMenuBarIcon"
    static let customMenuBarWord = "customMenuBarWord"
    static let useAlternativeMenuBarIcon = "useAlternativeMenuBarIcon"
    static let showNextTimerInMenuBar = "showNextTimerInMenuBar"
    static let playAlarmSound = "playAlarmSound"
    static let selectedAlarmSound = "selectedAlarmSound"
    static let loopAlarmUntilStopped = "loopAlarmUntilStopped"
    static let useCustomAlarmSound = "useCustomAlarmSound"
    static let customAlarmSoundBookmark = "customAlarmSoundBookmark"
    static let customAlarmSoundName = "customAlarmSoundName"
  }

  init() {
    loadPreferences()
    startAtLogin = SMAppService.mainApp.status == .enabled
    loadReminderData()
  }

  private func loadReminderData() {
    Task {
      await ensureReminderAccessAndFetchLists()
    }
  }

  private func ensureReminderAccessAndFetchLists() async {
    if allowReminders {
      await ensureReminderAccess()
      await fetchReminderLists()
      loadSelectedList()
    } else {
      await fetchReminderLists()
      loadSelectedList()
    }
  }

  func loadPreferences() {
    allowReminders = UserDefaults.standard.bool(forKey: Keys.allowReminders)
    deleteReminders = UserDefaults.standard.bool(forKey: Keys.deleteReminders)
    allowCustomNames = UserDefaults.standard.bool(forKey: Keys.allowCustomNames)
    allowSecondsMode = UserDefaults.standard.bool(forKey: Keys.allowSecondsMode)
    allowFiveMinuteMode = UserDefaults.standard.bool(
      forKey: Keys.allowFiveMinuteMode)
    viewAsMinutes = UserDefaults.standard.bool(forKey: Keys.viewAsMinutes)
    showDragIndicator = UserDefaults.standard.bool(
      forKey: Keys.showDragIndicator)
    changeRubberbandColor = UserDefaults.standard.bool(
      forKey: Keys.changeRubberbandColor)
    ignoreShortTimers = UserDefaults.standard.bool(
      forKey: Keys.ignoreShortTimers)
    shortTimerThresholdMinutes = UserDefaults.standard.double(
      forKey: Keys.shortTimerThresholdMinutes)
    if let colorData = UserDefaults.standard.data(forKey: "dragLineColor"),
      let color = try? NSKeyedUnarchiver.unarchivedObject(
        ofClass: NSColor.self, from: colorData)
    {
      dragLineColor = Color(nsColor: color)
    }
    useCustomMenuBarIcon = UserDefaults.standard.bool(forKey: Keys.useCustomMenuBarIcon)
    useAlternativeMenuBarIcon = UserDefaults.standard.bool(forKey: Keys.useAlternativeMenuBarIcon)
    customMenuBarWord = UserDefaults.standard.string(forKey: Keys.customMenuBarWord) ?? ""
    customMenuBarSymbol = UserDefaults.standard.string(forKey: Keys.customMenuBarSymbol) ?? ""
    useCustomMenuBarSymbol = UserDefaults.standard.bool(forKey: Keys.useCustomMenuBarSymbol)
    showNextTimerInMenuBar = UserDefaults.standard.bool(forKey: Keys.showNextTimerInMenuBar)
    playAlarmSound = UserDefaults.standard.bool(forKey: Keys.playAlarmSound)
    selectedAlarmSound =
    UserDefaults.standard.string(forKey: Keys.selectedAlarmSound) ?? ""
    loopAlarmUntilStopped = UserDefaults.standard.bool(
      forKey: Keys.loopAlarmUntilStopped)
    useCustomAlarmSound = UserDefaults.standard.bool(
      forKey: Keys.useCustomAlarmSound)
    customAlarmSoundName = UserDefaults.standard.string(
      forKey: Keys.customAlarmSoundName) ?? ""
    refreshAvailableAlarmSounds()
  }

  private func loadSelectedList() {
    let storedID = UserDefaults.standard.string(
      forKey: RemindersManager.selectedReminderListKey)
    if let storedList = RemindersManager.shared.fetchReminderLists().first(
      where: { $0.calendarIdentifier == storedID })
    {
      selectedList = storedList
    } else if reminderLists.isEmpty == false {
      selectedList = reminderLists.first
    }
  }

  /// 只写真正变化的值：原来每次保存都会重写全部偏好键。
  private func persist(_ value: Bool, forKey key: String) {
    if let stored = UserDefaults.standard.object(forKey: key) as? Bool,
      stored == value
    { return }
    UserDefaults.standard.set(value, forKey: key)
  }

  private func persist(_ value: String, forKey key: String) {
    if UserDefaults.standard.string(forKey: key) == value { return }
    UserDefaults.standard.set(value, forKey: key)
  }

  private func persist(_ value: Double, forKey key: String) {
    if let stored = UserDefaults.standard.object(forKey: key) as? Double,
      stored == value
    { return }
    UserDefaults.standard.set(value, forKey: key)
  }

  func savePreferences() {
    if let selected = selectedList {
      persist(
        selected.calendarIdentifier,
        forKey: RemindersManager.selectedReminderListKey)
    }
    persist(allowReminders, forKey: Keys.allowReminders)
    persist(deleteReminders, forKey: Keys.deleteReminders)
    persist(allowCustomNames, forKey: Keys.allowCustomNames)
    persist(ignoreShortTimers, forKey: Keys.ignoreShortTimers)
    persist(allowSecondsMode, forKey: Keys.allowSecondsMode)
    persist(allowFiveMinuteMode, forKey: Keys.allowFiveMinuteMode)
    persist(viewAsMinutes, forKey: Keys.viewAsMinutes)
    persist(showDragIndicator, forKey: Keys.showDragIndicator)
    persist(changeRubberbandColor, forKey: Keys.changeRubberbandColor)
    persist(
      shortTimerThresholdMinutes, forKey: Keys.shortTimerThresholdMinutes)
    persist(useCustomMenuBarIcon, forKey: Keys.useCustomMenuBarIcon)
    persist(customMenuBarWord, forKey: Keys.customMenuBarWord)
    persist(useAlternativeMenuBarIcon, forKey: Keys.useAlternativeMenuBarIcon)
    persist(useCustomMenuBarSymbol, forKey: Keys.useCustomMenuBarSymbol)
    persist(customMenuBarSymbol, forKey: Keys.customMenuBarSymbol)
    persist(showNextTimerInMenuBar, forKey: Keys.showNextTimerInMenuBar)
    persist(playAlarmSound, forKey: Keys.playAlarmSound)
    persist(selectedAlarmSound, forKey: Keys.selectedAlarmSound)
    persist(loopAlarmUntilStopped, forKey: Keys.loopAlarmUntilStopped)
    persist(useCustomAlarmSound, forKey: Keys.useCustomAlarmSound)
    persist(customAlarmSoundName, forKey: Keys.customAlarmSoundName)
    updateLoginItem()
    saveDragLineColor()
  }

  /// 文本类设置防抖保存，避免每敲一个字符就落盘一次。
  func schedulePreferencesSave() {
    pendingTextSave?.cancel()
    pendingTextSave = Just(())
      .delay(for: .milliseconds(300), scheduler: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.savePreferences()
      }
  }

  func ensureReminderAccess() async {
    let status = RemindersManager.shared.checkAuthorizationStatus()

    switch status {
    case .notDetermined:
      let granted = await RemindersManager.shared.requestAccess()
      if granted {
      } else {
        print("Access denied. Please enable it in System Settings.")
      }

    case .denied:
      print(
        "Reminders access denied. Ask the user to enable it in System Settings."
      )
    case .fullAccess, .writeOnly:
      break
    default:
      print("Unknown authorization status.")
    }
  }

  private func saveDragLineColor() {
    let nsColor = NSColor(dragLineColor)
    guard
      let colorData = try? NSKeyedArchiver.archivedData(
        withRootObject: nsColor, requiringSecureCoding: false)
    else { return }
    if UserDefaults.standard.data(forKey: "dragLineColor") == colorData {
      return
    }
    UserDefaults.standard.set(colorData, forKey: "dragLineColor")
  }

  func fetchReminderLists() async {
    await MainActor.run { [weak self] in
      guard let self = self else { return }
      self.reminderLists = RemindersManager.shared.fetchReminderLists()
    }
  }

  func refreshAvailableAlarmSounds() {
    availableAlarmSounds = SoundManager.shared.availableAlarmSounds()
    if !selectedAlarmSound.isEmpty
        && !availableAlarmSounds.contains(selectedAlarmSound)
    {
      selectedAlarmSound = availableAlarmSounds.first ?? ""
      savePreferences()
    } else if selectedAlarmSound.isEmpty {
      selectedAlarmSound = availableAlarmSounds.first ?? ""
    }
  }

  func displayName(for sound: String) -> String {
    URL(fileURLWithPath: sound).deletingPathExtension().lastPathComponent
  }

  func storeCustomAlarmSound(url: URL) {
    let startedAccess = url.startAccessingSecurityScopedResource()
    do {
      let bookmark = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
      DispatchQueue.main.async { [weak self] in
        UserDefaults.standard.set(
          bookmark, forKey: Keys.customAlarmSoundBookmark)
        self?.customAlarmSoundName = url.lastPathComponent
        self?.useCustomAlarmSound = true
        self?.savePreferences()
      }
    } catch {
      print("Failed to store custom alarm sound: \(error)")
    }
    if startedAccess {
      url.stopAccessingSecurityScopedResource()
    }
  }

  func updateLoginItem() {
    // 只在目标状态与系统实际状态不一致时才调用，避免每次保存都注册一遍。
    let currentlyEnabled = SMAppService.mainApp.status == .enabled
    guard startAtLogin != currentlyEnabled else { return }
    do {
      if startAtLogin {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      print(
        "Error \(startAtLogin ? "enabling" : "disabling") login item: \(error)")
      // 回读系统真实状态，避免盲目翻转导致开关自己乱跳。
      startAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}
