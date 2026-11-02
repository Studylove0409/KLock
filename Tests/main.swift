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

print("")
if failures == 0 {
  print("全部通过")
  exit(0)
} else {
  print("失败 \(failures) 项")
  exit(1)
}
