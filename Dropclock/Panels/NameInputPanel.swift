import AppKit
import SwiftUI

/// 开启「自定义计时器名称」时，拖拽松手后弹出的小输入框。
class NameInputPanel: NSObject {
  private var window: NSPanel?
  private var textField: NSTextField?
  private weak var delegate: NameInputPanelDelegate?

  private static let panelSize = NSSize(width: 248, height: 142)

  init(delegate: NameInputPanelDelegate) {
    self.delegate = delegate
  }

  func show(at point: NSPoint) {
    let size = Self.panelSize
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .floating
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.isMovableByWindowBackground = true
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // 同上：避免 close() 与 ARC 释放叠加导致崩溃。
    panel.isReleasedWhenClosed = false

    let blurView = NSVisualEffectView(
      frame: NSRect(origin: .zero, size: size))
    blurView.material = .hudWindow
    blurView.blendingMode = .behindWindow
    blurView.state = .active
    blurView.wantsLayer = true
    blurView.layer?.cornerRadius = 16
    blurView.layer?.cornerCurve = .continuous
    blurView.layer?.masksToBounds = true

    // 顶部到中段的高光，和其他面板保持同一种玻璃质感
    let sheen = CAGradientLayer()
    sheen.frame = CGRect(origin: .zero, size: size)
    sheen.colors = [
      NSColor.white.withAlphaComponent(0.10).cgColor,
      NSColor.white.withAlphaComponent(0).cgColor,
    ]
    sheen.startPoint = CGPoint(x: 0.5, y: 1)
    sheen.endPoint = CGPoint(x: 0.5, y: 0.45)
    blurView.layer?.addSublayer(sheen)

    let titleLabel = NSTextField(labelWithString: "计时器名称")
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = NSColor.white.withAlphaComponent(0.55)
    titleLabel.alignment = .left
    titleLabel.isBordered = false
    titleLabel.drawsBackground = false

    // 输入框外面套一层圆角容器：NSTextField 自己画不出连续圆角的玻璃底
    let fieldContainer = NSView()
    fieldContainer.wantsLayer = true
    fieldContainer.layer?.backgroundColor =
      NSColor.white.withAlphaComponent(0.10).cgColor
    fieldContainer.layer?.cornerRadius = 9
    fieldContainer.layer?.cornerCurve = .continuous
    fieldContainer.layer?.borderWidth = 1
    fieldContainer.layer?.borderColor =
      NSColor.white.withAlphaComponent(0.14).cgColor
    fieldContainer.translatesAutoresizingMaskIntoConstraints = false

    let textField = NSTextField()
    textField.placeholderString =
      "计时器 \(UserDefaults.standard.integer(forKey: "timerCount") + 1)"
    textField.font = NSFont.systemFont(ofSize: 13.5)
    textField.isEditable = true
    textField.isSelectable = true
    textField.delegate = self
    textField.isBordered = false
    textField.isBezeled = false
    textField.drawsBackground = false
    textField.backgroundColor = .clear
    textField.textColor = .white
    textField.focusRingType = .none
    textField.translatesAutoresizingMaskIntoConstraints = false
    fieldContainer.addSubview(textField)

    let cancelButton = NSButton(
      title: "取消", target: self, action: #selector(cancelNameInput))
    cancelButton.bezelStyle = .rounded
    cancelButton.controlSize = .large
    cancelButton.keyEquivalent = "\u{1b}"

    let createButton = NSButton(
      title: "开始", target: self, action: #selector(confirmNameInput))
    createButton.bezelStyle = .rounded
    createButton.controlSize = .large
    createButton.bezelColor = .controlAccentColor
    createButton.keyEquivalent = "\r"

    let buttonStack = NSStackView(views: [cancelButton, createButton])
    buttonStack.orientation = .horizontal
    buttonStack.spacing = 10
    buttonStack.distribution = .fillEqually

    let stack = NSStackView(views: [titleLabel, fieldContainer, buttonStack])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.setCustomSpacing(16, after: fieldContainer)
    stack.translatesAutoresizingMaskIntoConstraints = false

    blurView.addSubview(stack)
    panel.contentView?.addSubview(blurView)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: blurView.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: blurView.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(
        equalTo: blurView.topAnchor, constant: 20),
      fieldContainer.heightAnchor.constraint(equalToConstant: 34),
      fieldContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
      textField.leadingAnchor.constraint(
        equalTo: fieldContainer.leadingAnchor, constant: 10),
      textField.trailingAnchor.constraint(
        equalTo: fieldContainer.trailingAnchor, constant: -10),
      textField.centerYAnchor.constraint(
        equalTo: fieldContainer.centerYAnchor),
      titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
      buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
      buttonStack.heightAnchor.constraint(equalToConstant: 30),
    ])

    // 靠近屏幕边缘时把面板拉回可视区，否则输入框会跑到屏幕外
    let screen = NSScreen.screens.first { $0.frame.contains(point) }
      ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .zero
    var origin = NSPoint(x: point.x - size.width / 2, y: point.y - 120)
    if visible.width > 0, visible.height > 0 {
      let margin: CGFloat = 8
      origin.x = min(
        max(origin.x, visible.minX + margin),
        visible.maxX - size.width - margin)
      origin.y = min(
        max(origin.y, visible.minY + margin),
        visible.maxY - size.height - margin)
    }
    panel.setFrameOrigin(origin)

    panel.alphaValue = 0
    panel.orderFront(nil)
    panel.makeKeyAndOrderFront(nil)
    panel.level = .floating
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      panel.animator().alphaValue = 1
    }

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      panel.makeFirstResponder(textField)
    }

    self.window = panel
    self.textField = textField
  }

  @objc private func cancelNameInput() {
    cleanup()
    delegate?.nameInputPanelDidCancel()
  }

  @objc private func confirmNameInput() {
    let timerName =
      textField?.stringValue.isEmpty ?? true
      ? nil
      : textField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    cleanup()
    delegate?.nameInputPanelDidConfirm(name: timerName)
  }

  func cleanup() {
    window?.orderOut(nil)
    window?.close()
    window = nil
    textField = nil
  }
}

extension NameInputPanel: NSTextFieldDelegate {
  func control(
    _ control: NSControl, textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      confirmNameInput()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      cancelNameInput()
      return true
    }
    return false
  }
}

protocol NameInputPanelDelegate: AnyObject {
  func nameInputPanelDidConfirm(name: String?)
  func nameInputPanelDidCancel()
}
