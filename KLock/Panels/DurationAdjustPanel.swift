import AppKit

protocol DurationAdjustPanelDelegate: AnyObject {
  func durationAdjustPanelDidConfirm(duration: TimeInterval)
  func durationAdjustPanelDidCancel()
}

/// 松手后暂存时长，只有用户确认才继续创建计时器。
final class DurationAdjustPanel: NSObject {
  private weak var delegate: DurationAdjustPanelDelegate?
  private var panel: NSPanel?
  private var durationLabel: NSTextField?
  private var duration: TimeInterval
  private static let panelSize = NSSize(width: 296, height: 128)

  init(duration: TimeInterval, delegate: DurationAdjustPanelDelegate) {
    self.duration = TimerMath.adjustedDuration(duration, by: 0)
    self.delegate = delegate
  }

  func show(at point: NSPoint) {
    cleanup()
    let size = Self.panelSize
    let panel = GlassFloatingPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless],
      backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.isMovableByWindowBackground = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let chrome = Glass.makeGlassPanelChrome(frame: NSRect(origin: .zero, size: size))
    chrome.autoresizingMask = [.width, .height]

    let durationLabel = NSTextField(labelWithString: TimerTextFormatter.duration(duration))
    durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 33, weight: .semibold)
    durationLabel.textColor = .labelColor
    durationLabel.alignment = .center
    durationLabel.setAccessibilityLabel("当前时长")
    self.durationLabel = durationLabel

    let steps: [(String, Int, String)] = [
      ("−1分", -60, "减少 1 分钟"), ("−15秒", -15, "减少 15 秒"),
      ("+15秒", 15, "增加 15 秒"), ("+1分", 60, "增加 1 分钟"),
    ]
    let stepButtons = steps.map { title, delta, label -> NSView in
      let button = GlassButton(
        title: title, target: self, action: #selector(adjust(_:)), style: .step(decreasing: delta < 0))
      button.tag = delta
      button.setAccessibilityLabel(label)
      button.setContentHuggingPriority(.required, for: .horizontal)
      button.setContentCompressionResistancePriority(.required, for: .horizontal)
      return button
    }
    let stepStack = NSStackView(views: stepButtons)
    stepStack.orientation = .horizontal
    stepStack.alignment = .centerY
    stepStack.distribution = .fill
    stepStack.spacing = 8

    let cancel = GlassButton(
      title: "", target: self, action: #selector(cancelAdjustment), style: .close)
    cancel.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
    cancel.imagePosition = .imageOnly
    cancel.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
    cancel.contentTintColor = .secondaryLabelColor
    cancel.setAccessibilityLabel("取消")
    cancel.keyEquivalent = "\u{1b}"
    let confirm = GlassButton(
      title: "开始", target: self, action: #selector(confirmAdjustment), style: .start)
    confirm.keyEquivalent = "\r"
    for view in [durationLabel, stepStack, confirm, cancel] {
      view.translatesAutoresizingMaskIntoConstraints = false
      chrome.addSubview(view)
    }
    panel.contentView?.addSubview(chrome)
    NSLayoutConstraint.activate([
      // 文字框顶留 5pt，加上字体自身留白，数字视觉顶距约 14pt。
      durationLabel.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 5),
      durationLabel.centerXAnchor.constraint(equalTo: chrome.centerXAnchor),
      durationLabel.widthAnchor.constraint(equalTo: chrome.widthAnchor, constant: -80),
      durationLabel.heightAnchor.constraint(equalToConstant: 39),
      cancel.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 8),
      cancel.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 8),
      cancel.widthAnchor.constraint(equalToConstant: 26),
      cancel.heightAnchor.constraint(equalToConstant: 26),
      // 5 + 39 + 10 + 26 + 8 + 36 + 4pt 底距 = 128pt，保持三层面板尺寸。
      stepStack.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: 10),
      stepStack.centerXAnchor.constraint(equalTo: chrome.centerXAnchor),
      stepStack.leadingAnchor.constraint(greaterThanOrEqualTo: chrome.leadingAnchor, constant: 24),
      stepStack.trailingAnchor.constraint(lessThanOrEqualTo: chrome.trailingAnchor, constant: -24),
      stepStack.heightAnchor.constraint(equalToConstant: Glass.stepChipHeight),
      confirm.topAnchor.constraint(equalTo: stepStack.bottomAnchor, constant: 8),
      confirm.centerXAnchor.constraint(equalTo: chrome.centerXAnchor),
      confirm.widthAnchor.constraint(equalToConstant: 128),
      confirm.heightAnchor.constraint(equalToConstant: Glass.adjustStartHeight),
    ])
    NSLayoutConstraint.activate(
      stepButtons.map { $0.heightAnchor.constraint(equalTo: stepStack.heightAnchor) })

    let screen = ScreenPlacement.screenForMouse()
    let visible = screen?.visibleFrame ?? .zero
    let origin = Glass.clampedPanelOrigin(
      NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 10),
      size: size, visibleFrame: visible)
    panel.setFrameOrigin(origin)
    self.panel = panel
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(nil)
  }

  @objc private func adjust(_ sender: NSButton) {
    duration = TimerMath.adjustedDuration(duration, by: TimeInterval(sender.tag))
    durationLabel?.stringValue = TimerTextFormatter.duration(duration)
  }

  @objc private func cancelAdjustment() {
    let action = delegate
    cleanup()
    action?.durationAdjustPanelDidCancel()
  }

  @objc private func confirmAdjustment() {
    let value = duration
    let action = delegate
    cleanup()
    action?.durationAdjustPanelDidConfirm(duration: value)
  }

  func cleanup() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    durationLabel = nil
  }
}
