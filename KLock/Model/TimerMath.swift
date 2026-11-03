import Foundation

/// 计时相关的纯计算，单独放出来便于测试。
enum TimerMath {
  /// 普通拖拽用连续拖距判断磁吸，窗口之外仍保留原有的分段步进。
  static func snappedDragDuration(
    stepped: TimeInterval, continuous: TimeInterval, specialMode: Bool
  ) -> TimeInterval {
    guard stepped > 0, !specialMode else { return stepped }
    let targets: [TimeInterval] = [300, 600, 1500, 2700]
    return targets.first { abs(continuous - $0) <= 10 } ?? stepped
  }

  /// 微调保持秒级自由度，并限制在 1 秒到 7 天之间。
  static func adjustedDuration(_ duration: TimeInterval, by delta: TimeInterval) -> TimeInterval {
    min(7 * 24 * 60 * 60, max(1, duration + delta))
  }

  /// 剩余秒数；暂停时直接返回暂停时冻结的剩余时间。
  static func remaining(
    startTime: Date,
    duration: TimeInterval,
    pausedRemaining: TimeInterval?,
    now: Date
  ) -> TimeInterval {
    if let pausedRemaining = pausedRemaining {
      return max(0, pausedRemaining)
    }
    return startTime.addingTimeInterval(duration).timeIntervalSince(now)
  }

  /// 恢复计时后应该用的新的 startTime：让剩余时间保持不变。
  static func resumedStartTime(
    duration: TimeInterval,
    remaining: TimeInterval,
    now: Date
  ) -> Date {
    now.addingTimeInterval(remaining - duration)
  }
}
