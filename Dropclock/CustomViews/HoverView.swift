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
  private let isPaused: Bool
  private let onTogglePause: () -> Void
  private let onDelete: () -> Void

  private let pauseImage: NSImage?
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
    onTogglePause: @escaping () -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.isPaused = isPaused
    self.onTogglePause = onTogglePause
    self.onDelete = onDelete
    self.pauseImage = NSImage(
      systemSymbolName: isPaused ? "play.fill" : "pause.fill",
      accessibilityDescription: isPaused ? "继续" : "暂停")
    self.deleteImage = NSImage(
      systemSymbolName: "trash", accessibilityDescription: "删除")
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
      pauseImage, in: pauseRect, hovered: hoveredIcon == .pause,
      tint: .secondaryLabelColor)
    drawIcon(
      deleteImage, in: deleteRect, hovered: hoveredIcon == .delete,
      tint: .secondaryLabelColor)
  }

  private func drawIcon(
    _ image: NSImage?, in rect: NSRect, hovered: Bool, tint: NSColor
  ) {
    guard let image = image else { return }

    if hovered {
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
      let action = onDelete
      enclosingMenuItem?.menu?.cancelTracking()
      action()
    } else if pauseRect.contains(point) {
      let action = onTogglePause
      enclosingMenuItem?.menu?.cancelTracking()
      action()
    }
  }
}
