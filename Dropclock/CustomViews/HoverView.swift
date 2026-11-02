import AppKit

/// 菜单里的单行计时器：悬停时右侧浮出「暂停/继续」和「删除」两个图标。
///
/// 图标用独立 CALayer 承载，切换状态时叠一个淡入过渡，
/// 这样 ⏸ ↔ ▶ 是交叉淡化而不是硬切。
/// 不用 NSButton 是因为它的 tracking loop 会和菜单跟踪冲突。
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

  private let pauseLayer = CALayer()
  private let deleteLayer = CALayer()

  private var pauseRect: NSRect = .zero
  private var deleteRect: NSRect = .zero
  private var isHovering = false {
    didSet { needsDisplay = true }
  }
  private var hoveredIcon: Icon? {
    didSet { needsDisplay = true }
  }

  private static let iconSize: CGFloat = 10
  private static let iconWeight: NSFont.Weight = .regular
  private static let iconBox: CGFloat = 16
  private static let rightInset: CGFloat = 8
  private static let iconSpacing: CGFloat = 6

  /// 行宽固定：内容变化绝不能改变这一行的宽度，否则菜单整体会左右跳。
  static let rowWidth: CGFloat = 270
  static let rowHeight: CGFloat = 24

  override var intrinsicContentSize: NSSize {
    NSSize(width: Self.rowWidth, height: Self.rowHeight)
  }

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
    super.init(frame: frame)

    textField.isEditable = false
    textField.isBordered = false
    textField.drawsBackground = false
    textField.stringValue = text
    textField.font = NSFont.systemFont(ofSize: 13)
    textField.textColor = isPaused ? .secondaryLabelColor : .labelColor
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

    wantsLayer = true
    for iconLayer in [pauseLayer, deleteLayer] {
      iconLayer.contentsGravity = .center
      iconLayer.opacity = 0
      layer?.addSublayer(iconLayer)
    }
    refreshIconContents(animated: false)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - 布局

  override func layout() {
    super.layout()
    let y = (bounds.height - Self.iconBox) / 2
    deleteRect = NSRect(
      x: bounds.width - Self.rightInset - Self.iconBox, y: y,
      width: Self.iconBox, height: Self.iconBox)
    pauseRect = NSRect(
      x: deleteRect.minX - Self.iconSpacing - Self.iconBox, y: y,
      width: Self.iconBox, height: Self.iconBox)

    // CALayer 坐标与视图一致（同为非翻转），直接赋值即可
    pauseLayer.frame = pauseRect
    deleteLayer.frame = deleteRect
    updateLayerScale()
  }

  private func updateLayerScale() {
    let scale = currentScale
    pauseLayer.contentsScale = scale
    deleteLayer.contentsScale = scale
  }

  private var currentScale: CGFloat {
    window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateLayerScale()
    refreshIconContents(animated: false)
  }

  // MARK: - 图标内容

  private func refreshIconContents(animated: Bool) {
    let symbol = isPaused ? "play.fill" : "pause.fill"
    pauseLayer.contents = iconImage(symbol)
    deleteLayer.contents = iconImage("trash")

    if animated {
      let transition = CATransition()
      transition.type = .fade
      transition.duration = 0.18
      transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      pauseLayer.add(transition, forKey: "iconCrossFade")
    }
  }

  /// 把 SF Symbol 按屏幕缩放画进固定尺寸的位图并着色，返回 CGImage 供图层使用。
  /// 直接给图层设置 contentsScale，所以必须按像素尺寸渲染，否则 Retina 上会发虚。
  private func iconImage(_ name: String) -> CGImage? {
    let box = Self.iconBox
    let scale = currentScale
    let pixelSize = Int((box * scale).rounded())

    guard
      let context = CGContext(
        data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)
          ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let symbol = NSImage(
        systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(
          NSImage.SymbolConfiguration(
            pointSize: Self.iconSize, weight: Self.iconWeight))
    else { return nil }

    context.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(
      cgContext: context, flipped: false)

    let size = symbol.size
    let target = NSRect(
      x: (box - size.width) / 2, y: (box - size.height) / 2,
      width: size.width, height: size.height)
    symbol.draw(in: target)
    NSColor.secondaryLabelColor.set()
    target.fill(using: .sourceAtop)

    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()
  }

  // MARK: - 绘制（只负责悬停底衬）

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard isHovering else { return }

    if hoveredIcon == .pause {
      drawBackground(in: pauseRect)
    } else if hoveredIcon == .delete {
      drawBackground(in: deleteRect)
    }
  }

  private func drawBackground(in rect: NSRect) {
    let path = NSBezierPath(
      roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
    // 用 labelColor 做渐变，明暗模式下都能透出层次，而不是一块死板的灰
    let gradient = NSGradient(colors: [
      NSColor.labelColor.withAlphaComponent(0.13),
      NSColor.labelColor.withAlphaComponent(0.05),
    ])
    gradient?.draw(in: path, angle: -90)
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
    setIconOpacity(1, animated: false)
  }

  override func mouseExited(with event: NSEvent) {
    isHovering = false
    hoveredIcon = nil
    setIconOpacity(0, animated: false)
  }

  private func setIconOpacity(_ value: Float, animated: Bool) {
    if animated {
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = pauseLayer.opacity
      fade.toValue = value
      fade.duration = 0.12
      pauseLayer.add(fade, forKey: "opacity")
      deleteLayer.add(fade, forKey: "opacity")
    }
    pauseLayer.opacity = value
    deleteLayer.opacity = value
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
      // 立即切换状态再播动画：不依赖延时回调，菜单跟踪期间也一定生效
      let result = onTogglePause()
      apply(text: result.text, isPaused: result.isPaused)
    }
  }

  // MARK: - 原地更新

  /// 供外部每秒刷新文字用：只改内容，不播强调动画。
  func setContent(text: String, isPaused: Bool, animated: Bool = false) {
    let changed = isPaused != self.isPaused
    self.isPaused = isPaused
    textField.stringValue = text
    // 用颜色而不是追加文字来表示暂停：文字长度一变，行宽就会变，菜单会左右跳
    textField.textColor = isPaused ? .secondaryLabelColor : .labelColor
    if changed {
      refreshIconContents(animated: animated)
    }
  }

  private func apply(text: String, isPaused: Bool) {
    let changed = isPaused != self.isPaused
    setContent(text: text, isPaused: isPaused, animated: changed)

    // 文字跟着呼吸一下，避免硬切
    textField.alphaValue = 0.35
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      textField.animator().alphaValue = 1
    }
  }
}
