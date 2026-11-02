import AppKit

/// 计时结束后的强提醒窗口：屏幕居中、置顶、跨 Space 显示。
/// 不依赖系统通知权限，只要 app 在跑就一定看得见。
class ReminderAlertPanel {
  private var panel: NSPanel?
  private var onClose: (() -> Void)?
  private var onSnooze: ((Int) -> Void)?

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

    let size = NSSize(width: 440, height: 236)
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
    blur.layer?.cornerRadius = 22
    blur.layer?.masksToBounds = true
    blur.layer?.borderWidth = 1
    blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

    let caption = NSTextField(labelWithString: "提 醒")
    caption.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    caption.textColor = NSColor.white.withAlphaComponent(0.55)
    caption.alignment = .center

    let title = NSTextField(labelWithString: timerName)
    title.font = NSFont.systemFont(ofSize: 30, weight: .bold)
    title.textColor = .white
    title.alignment = .center
    title.lineBreakMode = .byTruncatingTail
    title.maximumNumberOfLines = 2
    title.cell?.wraps = true

    let subtitle = NSTextField(labelWithString: detail)
    subtitle.font = NSFont.systemFont(ofSize: 13)
    subtitle.textColor = NSColor.white.withAlphaComponent(0.6)
    subtitle.alignment = .center

    let closeButton = NSButton(
      title: "关闭", target: self, action: #selector(handleClose))
    closeButton.bezelStyle = .rounded
    closeButton.keyEquivalent = "\r"
    closeButton.controlSize = .large

    let snooze5Button = NSButton(
      title: "稍后 5 分钟", target: self, action: #selector(handleSnooze5))
    snooze5Button.bezelStyle = .rounded
    snooze5Button.controlSize = .large

    let snooze15Button = NSButton(
      title: "稍后 15 分钟", target: self, action: #selector(handleSnooze15))
    snooze15Button.bezelStyle = .rounded
    snooze15Button.controlSize = .large

    let buttonStack = NSStackView(
      views: [closeButton, snooze5Button, snooze15Button])
    buttonStack.orientation = .horizontal
    buttonStack.spacing = 10
    buttonStack.distribution = .fillEqually

    let stack = NSStackView(views: [caption, title, subtitle, buttonStack])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 10
    stack.setCustomSpacing(16, after: subtitle)
    stack.translatesAutoresizingMaskIntoConstraints = false

    blur.addSubview(stack)
    panel.contentView?.addSubview(blur)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 28),
      stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -28),
      stack.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
      buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
      title.widthAnchor.constraint(equalTo: stack.widthAnchor),
      subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])

    // 停在鼠标所在那块屏幕的正中央
    let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      let origin = NSPoint(
        x: visible.midX - size.width / 2,
        y: visible.midY - size.height / 2 + 40)
      panel.setFrameOrigin(origin)
    }

    panel.orderFrontRegardless()
    self.panel = panel
  }

  /// 静默关闭（例如对应计时器被手动删除）。
  func close() {
    cleanup()
  }

  @objc private func handleClose() {
    // 回调里外部会释放本对象，这里先持有强引用，避免方法执行中途被销毁。
    let alive = self
    let action = alive.onClose
    alive.cleanup()
    action?()
    _ = alive
  }

  @objc private func handleSnooze5() {
    handleSnooze(minutes: 5)
  }

  @objc private func handleSnooze15() {
    handleSnooze(minutes: 15)
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
