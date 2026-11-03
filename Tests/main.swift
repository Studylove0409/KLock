import AppKit

// 脱离 App 的逻辑自检：`bash scripts/test.sh` 运行。
// 只覆盖纯函数，UI 行为仍需人工验证。

var failures = 0

func expect(_ condition: Bool, _ label: String) {
  if condition {
    print("  ✓ \(label)")
  } else {
    print("  ✗ \(label)")
    failures += 1
  }
}

print("TimerTextFormatter.duration")
expect(TimerTextFormatter.duration(0) == "00:00", "0 秒 → 00:00")
expect(TimerTextFormatter.duration(59) == "00:59", "59 秒 → 00:59")
expect(TimerTextFormatter.duration(60) == "01:00", "60 秒 → 01:00")
expect(TimerTextFormatter.duration(3599) == "59:59", "3599 秒 → 59:59")
expect(TimerTextFormatter.duration(3600) == "1:00:00", "3600 秒 → 1:00:00")
expect(TimerTextFormatter.duration(-5) == "00:00", "负数按 0 处理")

print("TimerTextFormatter.truncated")
let font = NSFont.systemFont(ofSize: 13, weight: .medium)
let budget: CGFloat = 120
let longChinese = "给女朋友打电话提醒她交作业"
let cutChinese = TimerTextFormatter.truncated(
  longChinese, maxWidth: budget, font: font)
expect(
  TimerTextFormatter.width(of: cutChinese, font: font) <= budget,
  "中文长名截断后不超过预算")
expect(cutChinese.hasSuffix("…"), "超宽时补省略号")
expect(cutChinese.count < longChinese.count, "确实截短了")

let shortName = "泡面"
expect(
  TimerTextFormatter.truncated(shortName, maxWidth: budget, font: font)
    == shortName, "短名字不变")

let longLatin = "VeryLongTimerNameHereForTesting"
let cutLatin = TimerTextFormatter.truncated(
  longLatin, maxWidth: budget, font: font)
expect(
  TimerTextFormatter.width(of: cutLatin, font: font) <= budget,
  "英文长名截断后不超过预算")
expect(
  cutLatin.count > 12, "英文能比旧逻辑多吃到一些字符（旧逻辑固定 12 字）")

// MARK: - 历史记录

print("HistoryStore")
let now = Date()
let sample = [
  TimerRecord(
    name: "泡面", duration: 300, createdAt: now, status: .active),
  TimerRecord(
    name: "Meeting", duration: 3600, createdAt: now,
    finishedAt: now.addingTimeInterval(3600), status: .finished),
]
let encoded = HistoryStore.encode(sample)
expect(encoded != nil, "可以编码")
let decodedRecords = encoded.flatMap(HistoryStore.decode)
expect(decodedRecords?.count == 2, "可以解码回两条")
expect(decodedRecords?.first?.name == "泡面", "字段内容完整")
expect(decodedRecords?.first?.status == .active, "进行中状态保留")
expect(decodedRecords?.last?.finishedAt != nil, "结束时间保留")
expect(HistoryStore.decode(Data("不是 JSON".utf8)) == nil, "脏数据返回 nil")

// 旧存档只有 finishedAt，没有 createdAt / status
let legacyRecordJSON = """
[{"id":"\(UUID().uuidString)","name":"旧记录","duration":60,"finishedAt":800000000}]
""".data(using: .utf8)!
let legacyRecord = HistoryStore.decode(legacyRecordJSON)
expect(legacyRecord?.first?.status == .finished, "旧记录默认视为已完成")
expect(legacyRecord?.first?.createdAt != nil, "旧记录有兜底创建时间")

// MARK: - 暂停与恢复

print("TimerMath")
// 窗口边缘及特殊步进的行为会直接影响松手后的时长。
expect(
  TimerMath.snappedDragDuration(stepped: 270, continuous: 290, specialMode: false) == 300,
  "普通拖拽进入 5 分钟磁吸窗口时吸附")
expect(
  TimerMath.snappedDragDuration(stepped: 270, continuous: 289, specialMode: false) == 270,
  "磁吸窗口外保留原有步进")
expect(
  TimerMath.snappedDragDuration(stepped: 540, continuous: 592, specialMode: false) == 600,
  "普通拖拽吸附到 10 分钟")
expect(
  TimerMath.snappedDragDuration(stepped: 1440, continuous: 1492, specialMode: false) == 1500,
  "普通拖拽吸附到 25 分钟")
expect(
  TimerMath.snappedDragDuration(stepped: 2640, continuous: 2692, specialMode: false) == 2700,
  "普通拖拽吸附到 45 分钟")
expect(
  TimerMath.snappedDragDuration(stepped: 592, continuous: 592, specialMode: true) == 592,
  "特殊步进不被磁吸覆盖")
expect(TimerMath.adjustedDuration(120, by: 15) == 135, "微调不重新磁吸")
expect(TimerMath.adjustedDuration(3, by: -15) == 1, "微调不会小于 1 秒")
expect(TimerMath.adjustedDuration(604_790, by: 60) == 604_800, "微调不会超过 7 天")

let running = TimerMath.remaining(
  startTime: now.addingTimeInterval(-60), duration: 120,
  pausedRemaining: nil, now: now)
expect(abs(running - 60) < 0.01, "运行中剩余 60 秒")

let paused = TimerMath.remaining(
  startTime: now.addingTimeInterval(-60), duration: 120,
  pausedRemaining: 30, now: now.addingTimeInterval(100))
expect(abs(paused - 30) < 0.01, "暂停时返回冻结值，不随时间递减")

let resumedStart = TimerMath.resumedStartTime(
  duration: 120, remaining: 30, now: now)
let afterResume = TimerMath.remaining(
  startTime: resumedStart, duration: 120, pausedRemaining: nil, now: now)
expect(abs(afterResume - 30) < 0.01, "恢复后剩余时间保持不变")

// MARK: - 旧版存档兼容

print("SavedTimer 兼容性")
let legacyJSON = """
[{"id":"11111111-2222-3333-4444-555555555555","startTime":800000000,"duration":60}]
""".data(using: .utf8)!
let legacyDecoded = try? JSONDecoder().decode([SavedTimer].self, from: legacyJSON)
expect(legacyDecoded?.count == 1, "缺少 isFinished 的旧存档仍可解码")
expect(legacyDecoded?.first?.isFinished == nil, "旧存档的 isFinished 为 nil")

let finishedJSON = """
[{"id":"11111111-2222-3333-4444-555555555555","startTime":800000000,"duration":60,"isFinished":true}]
""".data(using: .utf8)!
let finishedDecoded = try? JSONDecoder().decode(
  [SavedTimer].self, from: finishedJSON)
expect(finishedDecoded?.first?.isFinished == true, "新存档能读回已结束标记")

print("")
if failures == 0 {
  print("全部通过")
  exit(0)
} else {
  print("失败 \(failures) 项")
  exit(1)
}
