import Foundation

// 回归测试只替代窗口，保留 AppDelegate 的排队和回调逻辑。
final class ReminderAlertPanel {
  private var onClose: (() -> Void)?
  private var onTimeout: (() -> Void)?
  private var onSnooze: ((Int) -> Void)?
  private var onPause: (() -> Void)?
  private var onDelete: (() -> Void)?

  func show(
    timerName: String,
    detail: String,
    onClose: @escaping () -> Void,
    onTimeout: @escaping () -> Void,
    onSnooze: @escaping (Int) -> Void,
    onPause: @escaping () -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.onClose = onClose
    self.onTimeout = onTimeout
    self.onSnooze = onSnooze
    self.onPause = onPause
    self.onDelete = onDelete
  }

  func close() {
    onClose = nil
    onTimeout = nil
    onSnooze = nil
    onPause = nil
    onDelete = nil
  }

  func simulateClose() {
    let action = onClose
    close()
    action?()
  }

  func simulateTimeout() {
    let action = onTimeout
    close()
    action?()
  }

  func simulateSnooze(_ minutes: Int) {
    let action = onSnooze
    close()
    action?(minutes)
  }

  func simulatePause() {
    let action = onPause
    close()
    action?()
  }

  func simulateDelete() {
    let action = onDelete
    close()
    action?()
  }
}
