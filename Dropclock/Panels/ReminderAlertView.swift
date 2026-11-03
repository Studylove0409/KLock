import SwiftUI

/// 屏幕下方逐渐变暗，上方保持透明。
struct ReminderBackdropView: View {
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.25),
            .init(color: .black.opacity(0.33), location: 0.65),
            .init(color: .black.opacity(0.64), location: 1),
          ], startPoint: .top, endPoint: .bottom
        )
        RadialGradient(
          colors: [.black.opacity(0.33), .clear],
          center: UnitPoint(x: 0.5, y: 0.38),
          startRadius: 0,
          endRadius: max(240, min(geometry.size.width, geometry.size.height) * 0.55)
        )
      }
    }
    .allowsHitTesting(false)
    .ignoresSafeArea()
  }
}

/// 渐变上的提醒标题和操作区。
struct ReminderAlertView: View {
  let timerName: String
  let detail: String
  let dismissAt: Date
  let dismissInterval: TimeInterval
  let onClose: () -> Void
  let onSnooze: (Int) -> Void
  let onPause: () -> Void
  let onDelete: () -> Void

  @State private var appeared = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.05)) { context in
      let remaining = max(0, dismissAt.timeIntervalSince(context.date))
      let progress = min(1, max(0, 1 - remaining / dismissInterval))
      let secondsRemaining = Int(ceil(remaining))

      VStack(spacing: 0) {
        Text("提醒")
          .font(.system(size: 11, weight: .medium))
          .tracking(2)
          .foregroundStyle(.white.opacity(0.62))
          .frame(maxWidth: 320)
          .overlay(alignment: .trailing) {
            Menu {
              Button(action: onPause) { Label("暂停", systemImage: "pause.fill") }
              Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
              }
            } label: {
              Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("更多操作")
            .accessibilityHint("暂停或删除计时器")
          }

        Text(timerName)
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .lineLimit(1)
          .truncationMode(.tail)
          .accessibilityLabel(timerName)
          .padding(.top, 8)

        Text(detail)
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.74))
          .lineLimit(1)
          .padding(.top, 7)

        HStack(spacing: 10) {
          AlertButton(
            title: "关", symbol: "xmark", kind: .primary,
            progress: progress, secondsRemaining: secondsRemaining, action: onClose)

          Menu {
            Button("5 分钟") { onSnooze(5) }
            Button("15 分钟") { onSnooze(15) }
          } label: {
            Label("稍后", systemImage: "clock.arrow.circlepath")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(.white.opacity(0.95))
              .frame(width: 155)
              .frame(height: Glass.primaryCapsuleHeight)
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
          .fixedSize()
          .frame(width: 155, height: Glass.primaryCapsuleHeight)
          .background(
            Capsule()
              .fill(Glass.alertButtonFill(primary: false, hovering: false, pressed: false))
          )
          .overlay(
            Capsule()
              .strokeBorder(
                Glass.alertButtonBorder(hovering: false), lineWidth: Glass.capsuleBorderWidth)
          )
          .contentShape(Capsule())
          .accessibilityLabel("稍后")
          .accessibilityHint("选择 5 分钟或 15 分钟后提醒")
        }
        .frame(maxWidth: 320)
        .padding(.top, 20)
      }
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .shadow(color: .black.opacity(0.24), radius: 12, y: 3)
    .opacity(appeared ? 1 : 0)
    .offset(y: appeared ? 0 : 8)
    .onAppear {
      if reduceMotion {
        appeared = true
      } else {
        withAnimation(.easeOut(duration: 0.22)) { appeared = true }
      }
    }
  }
}

/// 半透明按钮，让背景仍然透出来。
private struct AlertButton: View {
  enum Kind { case primary, secondary }

  let title: String
  let symbol: String
  let kind: Kind
  var progress: Double? = nil
  var secondsRemaining: Int? = nil
  let action: () -> Void

  @State private var isHovering = false
  @State private var isPressed = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let progress = progress {
          ZStack {
            Circle()
              .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
            Circle()
              .trim(from: 0, to: progress)
              .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
              .font(.system(size: 7, weight: .bold))
          }
          .frame(width: 16, height: 16)
          .accessibilityHidden(true)
        } else {
          Image(systemName: symbol)
            .accessibilityHidden(true)
        }
        Text(title)
      }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.95))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
        .frame(height: Glass.primaryCapsuleHeight)
        .background(
          Capsule()
            .fill(background)
        )
        .overlay(
          Capsule()
            .strokeBorder(
              Glass.alertButtonBorder(hovering: isHovering),
              lineWidth: Glass.capsuleBorderWidth)
        )
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
    .accessibilityValue(Text(secondsRemaining.map { "\($0) 秒后自动收起" } ?? ""))
    .onHover { isHovering = $0 }
    .simultaneousGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in isPressed = true }
        .onEnded { _ in isPressed = false }
    )
    .scaleEffect(isPressed ? 0.98 : 1)
  }

  private var background: Color {
    Glass.alertButtonFill(primary: kind == .primary, hovering: isHovering, pressed: isPressed)
  }
}
