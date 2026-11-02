import AppKit
import SwiftUI

/// 全应用统一的「玻璃」视觉参数。
///
/// 这里的思路是：窗口本身用 NSVisualEffectView 做毛玻璃，
/// 内容层只叠半透明填充 + 1pt 高光边，让背景透上来，
/// 而不是用不透明的 windowBackgroundColor 把玻璃盖住。
enum Glass {
  /// 卡片圆角（连续曲率，和系统一致）
  static let cardRadius: CGFloat = 12
  /// 行内边距
  static let rowInsets = EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14)

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
          .strokeBorder(Glass.border(scheme), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

extension View {
  func glassCard(radius: CGFloat = Glass.cardRadius) -> some View {
    modifier(GlassCard(radius: radius))
  }
}
