import AppKit
import SwiftUI

/// 计时结束后的强提醒窗口：屏幕居中、置顶、跨 Space 显示。
/// 不依赖系统通知权限，只要 app 在跑就一定看得见。
///
/// 底部是 AppKit 的毛玻璃（behindWindow 才能透出桌面），前景交给 SwiftUI。
class ReminderAlertPanel {
  private var panel: NSPanel?
  private var onClose: (() -> Void)?
  private var onSnooze: ((Int) -> Void)?

  /// 卡片宽度，内容纵向自适应
  private static let width: CGFloat = 420

  deinit {
    panel?.orderOut(nil)
    panel?.close()
  }

  func show(
    timerName: String,
    detail: String,
    onClose: @escaping () -> Void,
    onSnooze: @escaping (Int) -> Void
  ) {
    cleanup()
    self.onClose = onClose
    self.onSnooze = onSnooze

    let content = ReminderAlertView(
      timerName: timerName,
      detail: detail,
      onClose: { [weak self] in self?.handleClose() },
      onSnooze: { [weak self] minutes in self?.handleSnooze(minutes: minutes) }
    )
    .environment(\.colorScheme, .dark)
    .frame(width: Self.width)

    let host = NSHostingView(rootView: content)
    let fitting = host.fittingSize
    let size = NSSize(
      width: Self.width,
      height: fitting.height > 120 ? fitting.height : 280)

    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovableByWindowBackground = true
    panel.appearance = NSAppearance(named: .darkAqua)

    let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    blur.material = .hudWindow
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.wantsLayer = true
    blur.layer?.cornerRadius = 20
    blur.layer?.cornerCurve = .continuous
    blur.layer?.masksToBounds = true
    blur.layer?.borderWidth = 1
    blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

    // 顶部到中段的高光，让卡片看起来是「玻璃」而不是一块灰
    let sheen = CAGradientLayer()
    sheen.frame = CGRect(origin: .zero, size: size)
    sheen.colors = [
      NSColor.white.withAlphaComponent(0.10).cgColor,
      NSColor.white.withAlphaComponent(0).cgColor,
    ]
    sheen.startPoint = CGPoint(x: 0.5, y: 1)
    sheen.endPoint = CGPoint(x: 0.5, y: 0.5)
    blur.layer?.addSublayer(sheen)

    host.frame = NSRect(origin: .zero, size: size)
    host.autoresizingMask = [.width, .height]
    blur.addSubview(host)
    panel.contentView?.addSubview(blur)

    // 停在鼠标所在那块屏幕的正中央，稍微偏上
    let screen = NSScreen.screens.first {
      $0.frame.contains(NSEvent.mouseLocation)
    } ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      panel.setFrameOrigin(
        NSPoint(
          x: visible.midX - size.width / 2,
          y: visible.midY - size.height / 2 + 40))
    }

    panel.orderFrontRegardless()
    self.panel = panel
  }

  /// 静默关闭（例如对应计时器被手动删除）。
  func close() {
    cleanup()
  }

  private func handleClose() {
    // 回调里外部会释放本对象，这里先持有强引用，避免方法执行中途被销毁。
    let alive = self
    let action = alive.onClose
    alive.cleanup()
    action?()
    _ = alive
  }

  private func handleSnooze(minutes: Int) {
    let alive = self
    let action = alive.onSnooze
    alive.cleanup()
    action?(minutes)
    _ = alive
  }

  private func cleanup() {
    onClose = nil
    onSnooze = nil
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
  }
}
