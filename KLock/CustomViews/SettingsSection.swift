import SwiftUI

struct SettingsSection<Content: View>: View {
  let title: String
  let content: () -> Content

  init(title: String, @ViewBuilder content: @escaping () -> Content) {
    self.title = title
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.leading, 3)

      VStack(spacing: 0) {
        content()
      }
      .glassCard()
    }
  }
}
