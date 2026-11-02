import AppKit
import SwiftUI

/// 拖拽过程中跟随鼠标的时间预览。
class DragTimerPanel {
  private var panel: NSPanel?
  private var blurView: NSVisualEffectView?
  private var timerLabel: NSTextField?
  private var endTimeLabel: NSTextField?

  private static let panelHeight: CGFloat = 68
  private static let minWidth: CGFloat = 118
  private static let maxWidth: CGFloat = 250
  private static let timerFont = NSFont.monospacedDigitSystemFont(
    ofSize: 23, weight: .semibold)
  private static let endFont = NSFont.systemFont(ofSize: 11, weight: .medium)

  var frame: NSRect {
    return panel?.frame ?? .zero
  }

  func show() {
    cleanup()

    guard let screen = NSScreen.main else { return }
    let windowSize = NSSize(width: Self.minWidth, height: Self.panelHeight)
    let windowOrigin = NSPoint(
      x: screen.frame.midX - windowSize.width / 2,
      y: screen.frame.midY - windowSize.height / 2)

    let panel = NSPanel(
      contentRect: NSRect(origin: windowOrigin, size: windowSize),
      styleMask: [.nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovable = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // close() 时不让 AppKit 自行释放，否则与 ARC 的强引用叠加会造成过度释放。
    panel.isReleasedWhenClosed = false

    let blurView = NSVisualEffectView(
      frame: NSRect(origin: .zero, size: windowSize))
    blurView.material = .hudWindow
    blurView.blendingMode = .behindWindow
    blurView.state = .active
    blurView.wantsLayer = true
    blurView.layer?.cornerRadius = 16
    blurView.layer?.cornerCurve = .continuous
    blurView.layer?.masksToBounds = true
    blurView.layer?.borderWidth = 1
    blurView.layer?.borderColor =
      NSColor.white.withAlphaComponent(0.14).cgColor
    blurView.autoresizingMask = [.width, .height]
    self.blurView = blurView

    // 等宽数字，避免每帧跳动时文字宽度抖动
    let timerLabel = NSTextField(labelWithString: "00:00")
    timerLabel.font = Self.timerFont
    timerLabel.textColor = .white
    timerLabel.alignment = .center
    timerLabel.isBordered = false
    timerLabel.drawsBackground = false
    self.timerLabel = timerLabel

    let endTimeLabel = NSTextField(labelWithString: "结束于 12:00")
    endTimeLabel.font = Self.endFont
    endTimeLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    endTimeLabel.alignment = .center
    endTimeLabel.isBordered = false
    endTimeLabel.drawsBackground = false
    self.endTimeLabel = endTimeLabel

    let stackView = NSStackView(views: [timerLabel, endTimeLabel])
    stackView.orientation = .vertical
    stackView.alignment = .centerX
    stackView.spacing = 1
    stackView.translatesAutoresizingMaskIntoConstraints = false

    blurView.addSubview(stackView)
    panel.contentView?.addSubview(blurView)

    NSLayoutConstraint.activate([
      stackView.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
      stackView.centerYAnchor.constraint(equalTo: blurView.centerYAnchor),
      stackView.leadingAnchor.constraint(
        greaterThanOrEqualTo: blurView.leadingAnchor, constant: 14),
      stackView.trailingAnchor.constraint(
        lessThanOrEqualTo: blurView.trailingAnchor, constant: -14),
    ])

    panel.alphaValue = 0
    panel.orderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      panel.animator().alphaValue = 1
    }

    self.panel = panel
  }

  func update(timerText: String, endTimeText: String, at point: NSPoint) {
    DispatchQueue.main.async {
      self.timerLabel?.stringValue = timerText
      self.endTimeLabel?.stringValue = "结束于 \(endTimeText)"

      guard let panel = self.panel else { return }

      // 按文字实际宽度调整面板宽度，长文案（如「12 小时 45 分」）不会被截断
      let textWidth = max(
        TimerTextFormatter.width(of: timerText, font: Self.timerFont),
        TimerTextFormatter.width(
          of: "结束于 \(endTimeText)", font: Self.endFont))
      let targetWidth = min(Self.maxWidth, max(Self.minWidth, textWidth + 34))
      if abs(panel.frame.width - targetWidth) > 0.5 {
        var newFrame = panel.frame
        newFrame.size.width = targetWidth
        panel.setFrame(newFrame, display: true)
      }

      let windowWidth = panel.frame.width
      let windowHeight = panel.frame.height
      let newOrigin = NSPoint(
        x: point.x - windowWidth / 2,
        y: point.y - windowHeight / 2)
      panel.setFrameOrigin(newOrigin)
    }
  }

  func cleanup() {
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
  }
}
