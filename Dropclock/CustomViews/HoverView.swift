import AppKit

/// 菜单里的单行计时器：悬停时右侧浮出「暂停/继续」和「删除」两个图标。
///
/// 这里不用 NSButton：按钮自己的 tracking loop 会和菜单跟踪冲突，
/// 改成自绘图标 + 在 mouseDown 里做命中判断，行为完全可控。
final class HoverView: NSView {
  private enum Icon {
    case pause
    case delete
  }

  private let textField = NSTextField()
  private var isPaused: Bool
  /// 返回切换后的 (行文本, 是否暂停)，用于原地更新这一行
  private let onTogglePause: () -> (text: String, isPaused: Bool)
  private let onDelete: () -> Void

  private var pauseImage: NSImage?
  private let deleteImage: NSImage?

  private var pauseRect: NSRect = .zero
  private var deleteRect: NSRect = .zero
  private var isHovering = false {
    didSet { needsDisplay = true }
  }
  private var hoveredIcon: Icon? {
    didSet { needsDisplay = true }
  }

  private static let iconSize: CGFloat = 13
  private static let iconBox: CGFloat = 22
  private static let rightInset: CGFloat = 8
  private static let iconSpacing: CGFloat = 4

  init(
    text: String,
    isPaused: Bool,
    frame: NSRect,
    onTogglePause: @escaping () -> (text: String, isPaused: Bool),
    onDelete: @escaping () -> Void
  ) {
    self.isPaused = isPaused
    self.onTogglePause = onTogglePause
    self.onDelete = onDelete
    self.pauseImage = HoverView.symbol(
      isPaused ? "play.fill" : "pause.fill", isPaused ? "继续" : "暂停")
    self.deleteImage = HoverView.symbol("trash", "删除")
    super.init(frame: frame)

    textField.isEditable = false
    textField.isBordered = false
    textField.drawsBackground = false
    textField.stringValue = text
    textField.font = NSFont.systemFont(ofSize: 13)
    textField.textColor = .labelColor
    textField.lineBreakMode = .byTruncatingTail
    textField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(textField)

    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      textField.centerYAnchor.constraint(equalTo: centerYAnchor),
      textField.trailingAnchor.constraint(
        lessThanOrEqualTo: trailingAnchor,
        constant: -(Self.iconBox * 2 + Self.iconSpacing + Self.rightInset + 6)),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func symbol(_ name: String, _ description: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: description)
  }

  // MARK: - 布局与绘制

  override func layout() {
    super.layout()
    let y = (bounds.height - Self.iconBox) / 2
    deleteRect = NSRect(
      x: bounds.width - Self.rightInset - Self.iconBox, y: y,
      width: Self.iconBox, height: Self.iconBox)
    pauseRect = NSRect(
      x: deleteRect.minX - Self.iconSpacing - Self.iconBox, y: y,
      width: Self.iconBox, height: Self.iconBox)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard isHovering else { return }

    drawIcon(
      pauseImage, in: pauseRect, highlighted: hoveredIcon == .pause,
      tint: hoveredIcon == .pause ? .labelColor : .secondaryLabelColor)
    drawIcon(
      deleteImage, in: deleteRect, highlighted: hoveredIcon == .delete,
      tint: hoveredIcon == .delete ? .labelColor : .secondaryLabelColor)
  }

  private func drawIcon(
    _ image: NSImage?, in rect: NSRect, highlighted: Bool, tint: NSColor
  ) {
    guard let image = image else { return }

    if highlighted {
      let background = NSBezierPath(
        roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
      NSColor.labelColor.withAlphaComponent(0.1).setFill()
      background.fill()
    }

    let symbol = image.withSymbolConfiguration(
      NSImage.SymbolConfiguration(
        pointSize: Self.iconSize, weight: .medium)) ?? image
    let size = symbol.size
    let target = NSRect(
      x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
      width: size.width, height: size.height)

    let tinted = NSImage(size: target.size, flipped: false) { drawRect in
      symbol.draw(in: drawRect)
      tint.set()
      drawRect.fill(using: .sourceAtop)
      return true
    }
    tinted.draw(in: target)
  }

  // MARK: - 交互

  override func updateTrackingAreas() {
    for area in trackingAreas {
      removeTrackingArea(area)
    }
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [
          .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect,
        ],
        owner: self, userInfo: nil))
    super.updateTrackingAreas()
  }

  override func mouseEntered(with event: NSEvent) {
    isHovering = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovering = false
    hoveredIcon = nil
  }

  override func mouseMoved(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if deleteRect.contains(point) {
      hoveredIcon = .delete
    } else if pauseRect.contains(point) {
      hoveredIcon = .pause
    } else {
      hoveredIcon = nil
    }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)

    if deleteRect.contains(point) {
      // 删除会让整行消失，直接关菜单，行不见了本身就是反馈
      let action = onDelete
      enclosingMenuItem?.menu?.cancelTracking()
      action()
    } else if pauseRect.contains(point) {
      // 立即切换状态，再回放一次淡入作为反馈：
      // 不依赖延时回调，菜单跟踪期间也一定能生效
      let result = onTogglePause()
      apply(text: result.text, isPaused: result.isPaused)
    }
  }

  // MARK: - 原地更新

  private func apply(text: String, isPaused: Bool) {
    self.isPaused = isPaused
    pauseImage = HoverView.symbol(
      isPaused ? "play.fill" : "pause.fill", isPaused ? "继续" : "暂停")
    textField.stringValue = text
    needsDisplay = true

    // 轻微的一次呼吸，让图标和文字的变化被看见
    alphaValue = 0.55
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      animator().alphaValue = 1
    }
  }
}
