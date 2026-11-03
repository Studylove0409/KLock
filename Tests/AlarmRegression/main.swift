import AppKit

var failures = 0

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
  if condition() {
    print("  ✓ \(label)")
  } else {
    print("  ✗ \(label)")
    failures += 1
  }
}

final class TestSound: AlarmSoundPlaying {
  var loops = false
  var volume: Float = 0
  var isPlaying = false
  var stopCount = 0
  func play() -> Bool { isPlaying = true; return true }
  func stop() -> Bool { stopCount += 1; isPlaying = false; return true }
}

final class TestSounds {
  private var nextSound: TestSound?
  lazy var manager = SoundManager { [unowned self] _, _ in self.nextSound }

  func play(for id: UUID) -> TestSound {
    let sound = TestSound()
    nextSound = sound
    _ = manager.playSound(at: URL(fileURLWithPath: "/test-sound"), for: id, loop: true)
    nextSound = nil
    return sound
  }
}

final class CountingSoundManager: SoundManager {
  private(set) var playedIds: [UUID] = []

  override func playSelectedAlarmIfEnabled(for timerId: UUID, loop: Bool = false) {
    playedIds.append(timerId)
  }
}

func makeDelegate(loop: Bool) -> (AppDelegate, TestSounds) {
  let defaults = UserDefaults.standard
  defaults.set(true, forKey: "playAlarmSound")
  defaults.set(loop, forKey: "loopAlarmUntilStopped")
  defaults.set(false, forKey: "deleteReminders")
  defaults.set(false, forKey: "showNextTimerInMenuBar")
  let delegate = AppDelegate()
  delegate.notifyTimerFinished = { _ in }
  let sounds = TestSounds()
  delegate.soundManager = sounds.manager
  // 菜单打开期间真实代码会推迟重建，测试无需连接系统菜单栏。
  delegate.isMenuOpen = true
  return (delegate, sounds)
}

func timer(_ id: UUID, startTime: Date = Date(), paused: TimeInterval? = nil) -> (
  id: UUID, name: String?, startTime: Date, duration: TimeInterval,
  reminderId: String?, pausedRemaining: TimeInterval?, recordId: UUID?
) {
  (id, "测试", startTime, 60, nil, paused, nil)
}

func enqueue(_ delegate: AppDelegate, _ ids: [UUID]) {
  for id in ids {
    delegate.enqueueReminderAlert(timerId: id, name: "测试", duration: 60)
  }
}

print("多计时器声音回归测试")

do {
  let first = UUID(), second = UUID()
  let (delegate, sounds) = makeDelegate(loop: false)
  enqueue(delegate, [first, second])
  let firstSound = sounds.play(for: first), secondSound = sounds.play(for: second)
  delegate.reminderAlertPanel?.simulateClose()
  expect(!firstSound.isPlaying && secondSound.isPlaying, "关闭卡片只停止对应声音")
  expect(delegate.reminderAlertTimerId == second, "关闭卡片后显示下一条提醒")
  delegate.reminderAlertPanel?.simulateClose()
  expect(!secondSound.isPlaying, "关闭最后一条非循环提醒后停止对应声音")
}

do {
  let first = UUID(), second = UUID()
  let (delegate, sounds) = makeDelegate(loop: false)
  enqueue(delegate, [first, second])
  let firstSound = sounds.play(for: first), secondSound = sounds.play(for: second)
  delegate.reminderAlertPanel?.simulateTimeout()
  expect(!firstSound.isPlaying && secondSound.isPlaying, "自动收起只停止对应非循环声音")
  expect(delegate.reminderAlertTimerId == second, "自动收起后显示下一条提醒")
  delegate.reminderAlertPanel?.simulateTimeout()
  expect(!secondSound.isPlaying, "最后一条非循环提醒自动收起后停止对应声音")
}

do {
  let first = UUID(), second = UUID()
  let (delegate, sounds) = makeDelegate(loop: true)
  delegate.activeTimers = [timer(first), timer(second)]
  delegate.finishedTimerIds = [first, second]
  enqueue(delegate, [first, second])
  let firstSound = sounds.play(for: first), secondSound = sounds.play(for: second)
  delegate.reminderAlertPanel?.simulateClose()
  expect(!firstSound.isPlaying && secondSound.isPlaying, "关闭一个循环闹铃时保留另一个已结束闹铃的声音")
  expect(!delegate.finishedTimerIds.contains(first), "关闭循环提醒后移除该计时器")
  delegate.reminderAlertPanel?.simulateClose()
  expect(!secondSound.isPlaying, "关闭最后一个循环提醒后停止对应声音")
}

do {
  let current = UUID(), finished = UUID()
  let (delegate, sounds) = makeDelegate(loop: true)
  delegate.activeTimers = [timer(current), timer(finished)]
  delegate.finishedTimerIds = [current, finished]
  enqueue(delegate, [current])
  let currentSound = sounds.play(for: current), finishedSound = sounds.play(for: finished)
  delegate.reminderAlertPanel?.simulateClose()
  expect(!currentSound.isPlaying && finishedSound.isPlaying, "队列为空时，关闭一条提醒仍保留其他循环闹铃")
  delegate.deleteTimer(id: finished)
  expect(!finishedSound.isPlaying, "清除其他循环闹铃后停止对应声音")
}

do {
  let current = UUID(), finished = UUID()
  let (delegate, sounds) = makeDelegate(loop: true)
  delegate.activeTimers = [timer(finished)]
  delegate.finishedTimerIds = [finished]
  enqueue(delegate, [current])
  let currentSound = sounds.play(for: current), finishedSound = sounds.play(for: finished)
  delegate.reminderAlertPanel?.simulateTimeout()
  expect(!currentSound.isPlaying && finishedSound.isPlaying, "非循环卡片自动收起时保留其他循环闹铃")
  delegate.deleteTimer(id: finished)
  expect(!finishedSound.isPlaying, "删除剩余的循环闹铃后停止对应声音")
}

do {
  let finished = UUID(), unrelated = UUID()
  let (delegate, sounds) = makeDelegate(loop: true)
  delegate.activeTimers = [timer(finished), timer(unrelated)]
  delegate.finishedTimerIds = [finished]
  let sound = sounds.play(for: finished)
  delegate.deleteTimer(id: unrelated)
  expect(sound.isPlaying, "删除无关计时器时保留已结束循环闹铃的声音")
  delegate.deleteTimer(id: finished)
  expect(!sound.isPlaying, "删除最后一个循环闹铃后停止声音")
}

do {
  let current = UUID(), queued = UUID(), unrelated = UUID()
  let (delegate, sounds) = makeDelegate(loop: false)
  delegate.activeTimers = [timer(unrelated)]
  enqueue(delegate, [current, queued])
  let currentSound = sounds.play(for: current), queuedSound = sounds.play(for: queued)
  delegate.deleteTimer(id: unrelated)
  expect(currentSound.isPlaying && queuedSound.isPlaying, "删除无关计时器时保留排队提醒的声音")
  expect(delegate.reminderAlertTimerId == current, "删除无关计时器不会替换当前卡片")
  delegate.reminderAlertPanel?.simulateClose()
  delegate.reminderAlertPanel?.simulateClose()
  expect(!currentSound.isPlaying && !queuedSound.isPlaying, "排队提醒全部关闭后停止各自的声音")
}

for disabledKey in ["playAlarmSound", "loopAlarmUntilStopped"] {
  let finished = UUID(), unrelated = UUID()
  let (delegate, sounds) = makeDelegate(loop: true)
  delegate.activeTimers = [timer(finished), timer(unrelated)]
  delegate.finishedTimerIds = [finished]
  UserDefaults.standard.set(false, forKey: disabledKey)
  let sound = sounds.play(for: finished)
  delegate.deleteTimer(id: unrelated)
  expect(sound.isPlaying, "关闭 \(disabledKey) 后删除无关计时器仍不影响已播放的闹铃")
  delegate.deleteTimer(id: finished)
  expect(!sound.isPlaying, "删除对应计时器后停止已播放的闹铃")
}

do {
  let current = UUID(), queued = UUID()
  let (delegate, sounds) = makeDelegate(loop: false)
  // 当前卡片曾作为循环闹铃保留，随后用户关闭循环，另一条非循环提醒排队。
  delegate.activeTimers = [timer(current)]
  delegate.finishedTimerIds = [current]
  enqueue(delegate, [current, queued])
  let currentSound = sounds.play(for: current), queuedSound = sounds.play(for: queued)
  delegate.deleteTimer(id: current)
  expect(!currentSound.isPlaying && queuedSound.isPlaying, "删除当前卡片只停止当前提醒的声音")
  expect(delegate.reminderAlertTimerId == queued, "删除当前卡片后显示排队提醒")
  delegate.reminderAlertPanel?.simulateClose()
  expect(!queuedSound.isPlaying, "删除后关闭最后的提醒会停止对应声音")
}

do {
  let finished = UUID()
  let (delegate, sounds) = makeDelegate(loop: true)
  delegate.activeTimers = [timer(finished)]
  delegate.finishedTimerIds = [finished]
  enqueue(delegate, [finished])
  let sound = sounds.play(for: finished)
  delegate.reminderAlertPanel?.simulateTimeout()
  expect(sound.isPlaying, "循环闹铃自动收起卡片后继续保留声音")
  expect(delegate.finishedTimerIds.contains(finished), "循环闹铃自动收起后保留已结束条目")
  expect(delegate.activeTimers.contains { $0.id == finished }, "循环闹铃自动收起后仍可手动删除")
  delegate.deleteTimer(id: finished)
  expect(!sound.isPlaying, "手动删除自动收起的最后一个循环闹铃会停止声音")
}

do {
  let overdue = UUID(), paused = UUID(), future = UUID(), alreadyFinished = UUID()
  let (delegate, _) = makeDelegate(loop: false)
  let countingSounds = CountingSoundManager()
  delegate.soundManager = countingSounds
  var notifications = 0
  delegate.notifyTimerFinished = { _ in notifications += 1 }
  let past = Date().addingTimeInterval(-120)
  delegate.activeTimers = [
    timer(overdue, startTime: past), timer(paused, startTime: past, paused: 10),
    timer(future), timer(alreadyFinished, startTime: past),
  ]
  delegate.finishedTimerIds = [alreadyFinished]
  delegate.checkMissedDueTimers()
  delegate.checkMissedDueTimers()
  delegate.checkExpiredTimers()
  delegate.timerFinished(id: overdue)
  expect(notifications == 1 && countingSounds.playedIds == [overdue],
         "唤醒和普通 tick 只为未处理的到期计时器通知并响铃一次")
  expect(delegate.reminderAlertTimerId == overdue && delegate.pendingAlerts.isEmpty,
         "重复唤醒不会重复入队，暂停、未到期和已结束条目不会弹卡")
  expect(delegate.activeTimers.contains { $0.id == overdue }, "非循环到期条目在提醒操作前保留")
  delegate.reminderAlertPanel?.simulateTimeout()
  expect(!delegate.activeTimers.contains { $0.id == overdue }, "非循环提醒超时后移除到期条目")
}

do {
  let first = UUID(), second = UUID()
  let (delegate, sounds) = makeDelegate(loop: false)
  let past = Date().addingTimeInterval(-120)
  delegate.activeTimers = [timer(first, startTime: past), timer(second, startTime: past)]
  delegate.checkMissedDueTimers()
  let firstSound = sounds.play(for: first), secondSound = sounds.play(for: second)
  delegate.reminderAlertPanel?.simulatePause()
  expect(delegate.activeTimers.first { $0.id == first }?.pausedRemaining == 0,
         "非循环到期卡片暂停后保留冻结在零秒的计时器")
  expect(!delegate.finishedTimerIds.contains(first) && !firstSound.isPlaying && secondSound.isPlaying,
         "暂停解除已结束标记并只停止当前声音")
  let saved = UserDefaults.standard.data(forKey: "SavedTimers")
    .flatMap { try? JSONDecoder().decode([SavedTimer].self, from: $0) }
  expect(saved?.first { $0.id == first.uuidString }?.pausedRemaining == 0,
         "到期后暂停的计时器会以零秒暂停状态保存")
  expect(delegate.reminderAlertTimerId == second, "暂停后显示下一条卡片")
  delegate.checkMissedDueTimers()
  expect(delegate.pendingAlerts.isEmpty, "唤醒不会再次提醒已暂停的零秒计时器")
  delegate.reminderAlertPanel?.simulateClose()
  delegate.togglePause(id: first)
  delegate.checkMissedDueTimers()
  expect(delegate.reminderAlertTimerId == first, "恢复零秒计时器后会再次到期")
  delegate.reminderAlertPanel?.simulateClose()
}

do {
  let id = UUID()
  let (delegate, sounds) = makeDelegate(loop: true)
  delegate.activeTimers = [timer(id, startTime: Date().addingTimeInterval(-120))]
  delegate.checkMissedDueTimers()
  let sound = sounds.play(for: id)
  delegate.reminderAlertPanel?.simulatePause()
  expect(delegate.activeTimers.first?.pausedRemaining == 0
         && !delegate.finishedTimerIds.contains(id) && !sound.isPlaying,
         "循环到期卡片暂停后保留条目并停止循环声音")
}

do {
  let first = UUID(), second = UUID()
  let (delegate, sounds) = makeDelegate(loop: false)
  let past = Date().addingTimeInterval(-120)
  delegate.activeTimers = [timer(first, startTime: past), timer(second, startTime: past)]
  delegate.checkMissedDueTimers()
  let firstSound = sounds.play(for: first), secondSound = sounds.play(for: second)
  delegate.reminderAlertPanel?.simulateDelete()
  expect(!delegate.activeTimers.contains { $0.id == first } && !firstSound.isPlaying,
         "删除非循环到期卡片会移除条目并停止对应声音")
  expect(delegate.reminderAlertTimerId == second && secondSound.isPlaying,
         "删除当前卡片后继续显示下一条并保留其声音")
  delegate.reminderAlertPanel?.simulateSnooze(15)
  expect(!secondSound.isPlaying && delegate.activeTimers.contains { $0.duration == 900 && $0.name == "测试" },
         "稍后 15 分钟会停止当前声音并按原名称新建计时器")
}

do {
  let (delegate, sounds) = makeDelegate(loop: true)
  let first = sounds.play(for: UUID()), second = sounds.play(for: UUID())
  delegate.stopAllSounds()
  delegate.stopAllSounds()
  expect(!first.isPlaying && !second.isPlaying && first.stopCount == 1 && second.stopCount == 1,
         "停止全部响铃会停止并清理全部声音，重复操作安全")
  let later = sounds.play(for: UUID())
  expect(later.isPlaying, "停止全部响铃不会阻止后续计时器响铃")
  delegate.stopAllSounds()
}

do {
  let id = UUID()
  let (delegate, _) = makeDelegate(loop: false)
  delegate.activeTimers = [timer(id, startTime: Date().addingTimeInterval(-120))]
  delegate.checkMissedDueTimers()
  delegate.reminderAlertPanel?.simulateSnooze(5)
  expect(delegate.activeTimers.contains { $0.duration == 300 && $0.name == "测试" },
         "稍后 5 分钟按原名称新建 300 秒计时器")
}

if failures > 0 {
  print("声音回归测试失败 \(failures) 项")
  exit(1)
}
print("声音回归测试全部通过")
