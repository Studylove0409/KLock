import SwiftUI

/// 计时结束提醒卡片的内容层。
///
/// 卡片底下的毛玻璃由 AppKit 的 NSVisualEffectView 提供（必须 behindWindow
/// 才能透出桌面），这里只负责前景排版。
struct ReminderAlertView: View {
  let timerName: String
  let detail: String
  let onClose: () -> Void
  let onSnooze: (Int) -> Void

  @State private var appeared = false

  var body: some View {
    VStack(spacing: 0) {
      iconBadge
        .padding(.top, 30)

      Text("提 醒")
        .font(.system(size: 10.5, weight: .semibold))
        .kerning(2)
        .foregroundStyle(.white.opacity(0.5))
        .padding(.top, 16)

      Text(timerName)
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .padding(.top, 5)
        .padding(.horizontal, 26)

      Text(detail)
        .font(.system(size: 12.5))
        .foregroundStyle(.white.opacity(0.58))
        .padding(.top, 7)

      HStack(spacing: 9) {
        AlertButton(title: "关闭", kind: .primary, action: onClose)
        AlertButton(title: "稍后 5 分钟", kind: .secondary) { onSnooze(5) }
        AlertButton(title: "稍后 15 分钟", kind: .secondary) { onSnooze(15) }
      }
      .padding(.horizontal, 24)
      .padding(.top, 26)
      .padding(.bottom, 24)
    }
    .frame(maxWidth: .infinity)
    .opacity(appeared ? 1 : 0)
    .scaleEffect(appeared ? 1 : 0.96)
    .onAppear {
      withAnimation(.easeOut(duration: 0.18)) { appeared = true }
    }
  }

  /// 顶部的计时器徽章：半透明方块 + 细细的高光
  private var iconBadge: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .fill(Color.white.opacity(0.10))
        .overlay(
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(
              LinearGradient(
                colors: [Color.white.opacity(0.16), Color.clear],
                startPoint: .top, endPoint: .bottom))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )

      Image(systemName: "timer")
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(.white.opacity(0.92))
    }
    .frame(width: 54, height: 54)
  }
}

/// 卡片底部的胶囊按钮：主按钮实心，次按钮玻璃描边。
private struct AlertButton: View {
  enum Kind { case primary, secondary }

  let title: String
  let kind: Kind
  let action: () -> Void

  @State private var isHovering = false
  @State private var isPressed = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(
          kind == .primary ? Color.black.opacity(0.85) : Color.white.opacity(0.92)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(background)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
              kind == .secondary
                ? Color.white.opacity(isHovering ? 0.26 : 0.16) : Color.clear,
              lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in isPressed = true }
        .onEnded { _ in isPressed = false }
    )
    .scaleEffect(isPressed ? 0.98 : 1)
  }

  private var background: Color {
    switch kind {
    case .primary:
      return Color.white.opacity(isPressed ? 0.72 : (isHovering ? 1.0 : 0.92))
    case .secondary:
      return Color.white.opacity(isPressed ? 0.24 : (isHovering ? 0.16 : 0.10))
    }
  }
}
