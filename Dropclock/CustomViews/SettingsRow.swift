import SwiftUI

/// 设置项：左侧标题 + 帮助气泡，右侧控件。
/// 悬停时整行有极淡的高光，和系统设置的手感一致。
struct SettingsRow<Content: View>: View {
  let title: String
  let helpText: String
  let content: () -> Content
  /// 卡片里除第一行外都画一条顶部细线，和系统设置一致
  let showsTopDivider: Bool
  @State private var isShowingHelp = false
  @State private var isHovering = false

  init(
    title: String, showsTopDivider: Bool = true, helpText: String,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.helpText = helpText
    self.showsTopDivider = showsTopDivider
    self.content = content
  }

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 5) {
        Text(title)
          .font(.system(size: 12.5))
          .foregroundStyle(.primary)
        Button {
          isShowingHelp.toggle()
        } label: {
          Image(systemName: "questionmark.circle")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingHelp, arrowEdge: .top) {
          Text(helpText)
            .font(.system(size: 12))
            .multilineTextAlignment(.leading)
            .lineLimit(4)
            .frame(width: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
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
