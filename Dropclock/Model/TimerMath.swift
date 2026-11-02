import Foundation

/// 计时相关的纯计算，单独放出来便于测试。
enum TimerMath {

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
