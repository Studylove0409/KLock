import AppKit
import SwiftUI

/// 全应用统一的「玻璃」视觉参数。
///
/// 这里的思路是：窗口本身用 NSVisualEffectView 做毛玻璃，
/// 内容层只叠半透明填充和轻描边，让背景透上来，
/// 而不是用不透明的 windowBackgroundColor 把玻璃盖住。
enum Glass {
  /// 面板、卡片和行内控件有明确的圆角层级。
  static let panelRadius: CGFloat = 22
  static let cardRadius: CGFloat = 12
  static let buttonRadius: CGFloat = 9
  static let stepChipHeight: CGFloat = 26
  /// 命名条与提醒按钮继续使用主胶囊高度。
  static let primaryCapsuleHeight: CGFloat = 42
  /// 微调面板的「开始」使用更紧凑的独立高度。
  static let adjustStartHeight: CGFloat = 36
  static let sidebarSelectionRadius: CGFloat = 8
  static let borderWidth: CGFloat = 1
  static let capsuleBorderWidth: CGFloat = 0.5
  static let panelMaterial: NSVisualEffectView.Material = .hudWindow
  /// 行内边距
  static let rowInsets = EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14)

  static func capsuleRadius(for height: CGFloat) -> CGFloat { height / 2 }

  static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  static func panelBorder(_ appearance: NSAppearance) -> NSColor {
    isDark(appearance)
      ? NSColor.white.withAlphaComponent(0.10)
      : NSColor.black.withAlphaComponent(0.10)
  }

  static func controlFill(_ appearance: NSAppearance) -> NSColor {
    isDark(appearance)
      ? NSColor.white.withAlphaComponent(0.10)
      : NSColor.black.withAlphaComponent(0.055)
  }

  static func panelSheen(_ appearance: NSAppearance) -> [CGColor] {
    [NSColor.white.withAlphaComponent(isDark(appearance) ? 0.07 : 0.22).cgColor,
     NSColor.clear.cgColor]
  }

  static func configureMaterial(_ view: NSVisualEffectView) {
    view.material = panelMaterial
    view.blendingMode = .behindWindow
    view.state = .active
  }

  static func makeGlassPanelChrome(frame: NSRect, capsule: Bool = false) -> NSVisualEffectView {
    GlassPanelChrome(frame: frame, capsule: capsule)
  }

  static func clampedPanelOrigin(
    _ origin: NSPoint, size: NSSize, visibleFrame: NSRect, margin: CGFloat = 8
  ) -> NSPoint {
    guard visibleFrame.width > 0, visibleFrame.height > 0 else { return origin }
    let minX = visibleFrame.minX + margin
    let minY = visibleFrame.minY + margin
    let maxX = max(minX, visibleFrame.maxX - size.width - margin)
    let maxY = max(minY, visibleFrame.maxY - size.height - margin)
    return NSPoint(x: min(max(origin.x, minX), maxX), y: min(max(origin.y, minY), maxY))
  }

  /// 提醒覆盖层固定深色；使用同一组按钮令牌而不改变原有动作。
  static func alertButtonBorder(hovering: Bool) -> Color {
    Color.white.opacity(hovering ? 0.12 : 0.08)
  }

  static func alertButtonFill(primary: Bool, hovering: Bool, pressed: Bool) -> Color {
    if primary {
      return Color.white.opacity(pressed ? 0.26 : (hovering ? 0.22 : 0.16))
    }
    return Color.white.opacity(pressed ? 0.12 : (hovering ? 0.11 : 0.10))
  }

  /// 细到几乎看不见的描边，靠它把卡片从背景里「立」起来
  static func border(_ scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color.white.opacity(0.09)
      : Color.black.opacity(0.08)
  }

  /// 顶部到透明的高光渐变，模拟玻璃受光
  static func sheen(_ scheme: ColorScheme) -> LinearGradient {
    LinearGradient(
      colors: [
        Color.white.opacity(scheme == .dark ? 0.075 : 0.45),
        Color.white.opacity(0),
      ],
      startPoint: .top,
      endPoint: .bottom)
  }

  /// 卡片底色：跟随明暗模式的一点点「浑浊」
  static func cardFill(_ scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color.white.opacity(0.045)
      : Color.white.opacity(0.65)
  }

  /// 选中态填充：用系统强调色，跟随用户在「外观」里选的颜色
  static func selectionFill(_ scheme: ColorScheme) -> Color {
    Color.accentColor.opacity(scheme == .dark ? 0.28 : 0.18)
  }
}

/// AppKit 面板共用的材质、连续圆角、描边和随尺寸变化的高光。
private final class GlassPanelChrome: NSVisualEffectView {
  private let sheenLayer = CAGradientLayer()
  private let capsule: Bool

  init(frame frameRect: NSRect, capsule: Bool) {
    self.capsule = capsule
    super.init(frame: frameRect)
    Glass.configureMaterial(self)
    wantsLayer = true
    layer?.cornerRadius = capsule ? Glass.capsuleRadius(for: frameRect.height) : Glass.panelRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = Glass.capsuleBorderWidth
    sheenLayer.startPoint = CGPoint(x: 0.5, y: 1)
    sheenLayer.endPoint = CGPoint(x: 0.5, y: 0.45)
    layer?.addSublayer(sheenLayer)
    updateColors()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = capsule ? Glass.capsuleRadius(for: bounds.height) : Glass.panelRadius
    sheenLayer.frame = bounds
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.borderColor = Glass.panelBorder(effectiveAppearance).cgColor
      sheenLayer.colors = Glass.panelSheen(effectiveAppearance)
    }
  }
}

/// 无标题栏仍可接收输入焦点和原生按钮快捷键。
final class GlassFloatingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

/// 与提醒按钮同系的 AppKit 玻璃按钮，保留系统键盘和辅助功能行为。
final class GlassButton: NSButton {
  enum Style {
    case standard
    case step(decreasing: Bool)
    case start
    case close
  }

  private let emphasized: Bool
  private let style: Style

  // NSButton 的图标对齐留白会把约束的 30pt 扩成 35pt；胶囊按实际外框布局。
  override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

  init(
    title: String, target: AnyObject?, action: Selector?, emphasized: Bool = false,
    style: Style = .standard
  ) {
    self.emphasized = emphasized
    self.style = style
    super.init(frame: .zero)
    self.title = title
    self.target = target
    self.action = action
    isBordered = false
    wantsLayer = true
    switch style {
    case .standard:
      font = NSFont.systemFont(ofSize: 12, weight: .medium)
      layer?.borderWidth = Glass.capsuleBorderWidth
    case .step:
      font = NSFont.systemFont(ofSize: 11, weight: .medium)
    case .start:
      font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    case .close:
      font = NSFont.systemFont(ofSize: 11, weight: .medium)
    }
    layer?.cornerRadius = Glass.capsuleRadius(for: Glass.primaryCapsuleHeight)
    layer?.cornerCurve = .continuous
    updateColors()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: NSSize {
    if case .step = style {
      let width = (title as NSString).size(withAttributes: [.font: font!]).width
      return NSSize(width: ceil(width) + 24, height: Glass.stepChipHeight)
    }
    return super.intrinsicContentSize
  }

  override var isHighlighted: Bool {
    didSet { updateColors() }
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = Glass.capsuleRadius(for: bounds.height)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let fill: NSColor
      let textColor: NSColor
      switch style {
      case .standard:
        fill = emphasized
          ? NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.26 : 0.18)
          : NSColor.white.withAlphaComponent(isHighlighted ? 0.12 : 0.10)
        textColor = .labelColor
      case .step(let decreasing):
        fill = (Glass.isDark(effectiveAppearance) ? NSColor.white : NSColor.black)
          .withAlphaComponent(isHighlighted ? 0.08 : 0.07)
        textColor = decreasing ? .secondaryLabelColor : .labelColor
      case .start:
        fill = NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.50 : 0.42)
        textColor = .labelColor
      case .close:
        fill = isHighlighted ? Glass.controlFill(effectiveAppearance) : .clear
        textColor = .secondaryLabelColor
        contentTintColor = textColor
      }
      layer?.backgroundColor = fill.cgColor
      layer?.borderColor = Glass.panelBorder(effectiveAppearance).cgColor
      attributedTitle = NSAttributedString(
        string: title,
        attributes: [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium),
                     .foregroundColor: textColor])
    }
  }
}

final class GlassFieldContainer: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = Glass.capsuleRadius(for: frameRect.height)
    layer?.cornerCurve = .continuous
    updateColors()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = Glass.capsuleRadius(for: bounds.height)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = Glass.controlFill(effectiveAppearance).cgColor
      layer?.borderColor = Glass.panelBorder(effectiveAppearance).cgColor
    }
  }
}

/// 给 SwiftUI 用的毛玻璃底板。
struct GlassBackground: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .sidebar
  var blending: NSVisualEffectView.BlendingMode = .behindWindow

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blending
    view.state = .active
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.material = material
    view.blendingMode = blending
  }
}

/// 卡片容器：半透明底 + 顶部高光 + 细描边。
struct GlassCard: ViewModifier {
  @Environment(\.colorScheme) private var scheme
  var radius: CGFloat = Glass.cardRadius

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(Glass.cardFill(scheme))
          .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
              .fill(Glass.sheen(scheme))
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Glass.border(scheme), lineWidth: Glass.borderWidth)
      )
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

extension View {
  func glassCard(radius: CGFloat = Glass.cardRadius) -> some View {
    modifier(GlassCard(radius: radius))
  }
}
