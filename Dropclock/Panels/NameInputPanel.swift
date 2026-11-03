import AppKit
import SwiftUI

/// 开启「自定义计时器名称」时，拖拽松手后弹出的小输入框。
class NameInputPanel: NSObject {
  private var window: NSPanel?
  private var textField: NSTextField?
  private weak var delegate: NameInputPanelDelegate?

  private static let panelSize = NSSize(width: 396, height: Glass.primaryCapsuleHeight)

  init(delegate: NameInputPanelDelegate) {
    self.delegate = delegate
  }

  func show(at point: NSPoint, duration: TimeInterval) {
    cleanup()
    let size = Self.panelSize
    let panel = GlassFloatingPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    panel.isFloatingPanel = true
    panel.level = .floating
    panel.isMovableByWindowBackground = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // 同上：避免 close() 与 ARC 释放叠加导致崩溃。
    panel.isReleasedWhenClosed = false

    let content = NSView(frame: NSRect(origin: .zero, size: size))
    panel.contentView = content
    let cancelGlass = Glass.makeGlassPanelChrome(frame: .zero, capsule: true)
    let capsule = Glass.makeGlassPanelChrome(frame: .zero, capsule: true)
    content.addSubview(cancelGlass)
    content.addSubview(capsule)

    let chip = GlassFieldContainer(frame: .zero)
    let timerIcon = NSImageView()
    timerIcon.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
    timerIcon.contentTintColor = .secondaryLabelColor
    timerIcon.setAccessibilityElement(false)
    let timeLabel = NSTextField(labelWithString: TimerTextFormatter.duration(duration))
    timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    timeLabel.textColor = .labelColor
    timeLabel.setAccessibilityLabel("拟用时长")
    let chipContent = NSStackView(views: [timerIcon, timeLabel])
    chipContent.orientation = .horizontal
    chipContent.alignment = .centerY
    chipContent.spacing = 6
    chip.addSubview(chipContent)
    capsule.addSubview(chip)

    let textField = NSTextField()
    let placeholder = "计时器 \(UserDefaults.standard.integer(forKey: "timerCount") + 1)"
    textField.placeholderAttributedString = NSAttributedString(
      string: placeholder, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
    textField.font = NSFont.systemFont(ofSize: 15)
    textField.setAccessibilityLabel("计时器名称")
    textField.setAccessibilityHelp("输入名称后按 Return 开始，按 Escape 取消")
    textField.isEditable = true
    textField.isSelectable = true
    textField.delegate = self
    textField.isBordered = false
    textField.isBezeled = false
    textField.drawsBackground = false
    textField.backgroundColor = .clear
    textField.textColor = .labelColor
    textField.focusRingType = .none
    textField.usesSingleLineMode = true
    textField.cell?.isScrollable = true
    textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    capsule.addSubview(textField)

    let cancelButton = GlassButton(
      title: "", target: self, action: #selector(cancelNameInput))
    cancelButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
    cancelButton.imagePosition = .imageOnly
    cancelButton.contentTintColor = .labelColor
    cancelButton.setAccessibilityLabel("取消")
    cancelButton.keyEquivalent = "\u{1b}"
    cancelGlass.addSubview(cancelButton)

    let createButton = GlassButton(
      title: "", target: self, action: #selector(confirmNameInput), emphasized: true)
    createButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
    createButton.imagePosition = .imageOnly
    createButton.contentTintColor = .controlAccentColor
    createButton.setAccessibilityLabel("开始")
    createButton.keyEquivalent = "\r"
    capsule.addSubview(createButton)
    for view in [cancelGlass, capsule, chip, chipContent, timerIcon, textField,
                 cancelButton, createButton] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }

    NSLayoutConstraint.activate([
      cancelGlass.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      cancelGlass.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      cancelGlass.widthAnchor.constraint(equalToConstant: 36),
      cancelGlass.heightAnchor.constraint(equalToConstant: 36),
      cancelButton.widthAnchor.constraint(equalTo: cancelGlass.widthAnchor),
      cancelButton.heightAnchor.constraint(equalTo: cancelGlass.heightAnchor),
      cancelButton.centerXAnchor.constraint(equalTo: cancelGlass.centerXAnchor),
      cancelButton.centerYAnchor.constraint(equalTo: cancelGlass.centerYAnchor),
      capsule.leadingAnchor.constraint(equalTo: cancelGlass.trailingAnchor, constant: 8),
      capsule.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      capsule.topAnchor.constraint(equalTo: content.topAnchor),
      capsule.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      chip.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 5),
      chip.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
      chip.heightAnchor.constraint(equalToConstant: 32),
      chipContent.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10),
      chipContent.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
      chipContent.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
      timerIcon.widthAnchor.constraint(equalToConstant: 16),
      timerIcon.heightAnchor.constraint(equalToConstant: 16),
      textField.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 9),
      textField.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -5),
      textField.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
      createButton.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -6),
      createButton.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
      createButton.widthAnchor.constraint(equalToConstant: 30),
      createButton.heightAnchor.constraint(equalToConstant: 30),
    ])

    // 靠近屏幕边缘时把面板拉回可视区，否则输入框会跑到屏幕外
    let screen = ScreenPlacement.screenForMouse()
    let visible = screen?.visibleFrame ?? .zero
    let origin = Glass.clampedPanelOrigin(
      NSPoint(x: point.x - size.width / 2, y: point.y - size.height + 22),
      size: size, visibleFrame: visible)
    panel.setFrameOrigin(origin)

    panel.alphaValue = 0
    panel.orderFront(nil)
    panel.makeKeyAndOrderFront(nil)
    panel.level = .floating
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      panel.animator().alphaValue = 1
    }

    self.window = panel
    self.textField = textField
    DispatchQueue.main.async { [weak self, weak panel, weak textField] in
      guard let self = self, let panel = panel, let textField = textField,
        self.window === panel else { return }
      NSApp.activate(ignoringOtherApps: true)
      panel.makeFirstResponder(textField)
    }
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
