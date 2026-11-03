import SwiftUI

/// 设置项：左侧标题 + 帮助气泡，右侧控件。
/// 悬停时整行有极淡的高光，和系统设置的手感一致。
struct SettingsRow<Content: View>: View {
  let title: String
  let subtitle: String?
  let subtitleColor: Color
  let helpText: String?
  let content: () -> Content
  /// 卡片里除第一行外都画一条顶部细线，和系统设置一致
  let showsTopDivider: Bool
  @State private var isShowingHelp = false
  @State private var isHovering = false

  init(
    title: String, subtitle: String? = nil, subtitleColor: Color = .secondary,
    showsTopDivider: Bool = true,
    helpText: String? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.subtitleColor = subtitleColor
    self.helpText = helpText
    self.showsTopDivider = showsTopDivider
    self.content = content
  }

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 5) {
          Text(title)
            .font(.system(size: 12.5))
            .foregroundStyle(.primary)
          if let helpText = helpText {
            Button {
              isShowingHelp.toggle()
            } label: {
              Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(title)说明"))
            .accessibilityHint(Text("显示此设置的详细说明"))
            .popover(isPresented: $isShowingHelp, arrowEdge: .top) {
              Text(helpText)
                .font(.system(size: 12))
                .multilineTextAlignment(.leading)
                .frame(width: 260, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
            }
          }
        }
        if let subtitle = subtitle {
          Text(subtitle)
            .font(.system(size: 11.5))
            .foregroundStyle(subtitleColor)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 12)
      content()
    }
    .padding(Glass.rowInsets)
    .background(isHovering ? Color.primary.opacity(0.035) : Color.clear)
    .overlay(alignment: .top) {
      if showsTopDivider {
        Rectangle()
          .fill(Color.primary.opacity(0.07))
          .frame(height: 1)
          .padding(.leading, 14)
      }
    }
    .onHover { isHovering = $0 }
  }
}
