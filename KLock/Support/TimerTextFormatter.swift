import AppKit

/// 与界面无关的文本格式化逻辑，抽出来单独放，便于脱离 App 运行测试。
enum TimerTextFormatter {

  /// 把剩余秒数格式化成 mm:ss，超过一小时则用 h:mm:ss。
  static func duration(_ timeInterval: TimeInterval) -> String {
    let totalSeconds = Int(max(0, timeInterval))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }

  /// 按指定字体渲染后的实际宽度（pt）。
  static func width(of text: String, font: NSFont) -> CGFloat {
    NSAttributedString(string: text, attributes: [.font: font]).size().width
  }

  /// 按渲染宽度截断，超宽时保留省略号。
  static func truncated(
    _ name: String, maxWidth: CGFloat, font: NSFont
  ) -> String {
    guard width(of: name, font: font) > maxWidth else { return name }

    let ellipsis = "…"
    var kept = name
    while !kept.isEmpty {
      kept.removeLast()
      let candidate = kept + ellipsis
      if width(of: candidate, font: font) <= maxWidth { return candidate }
    }
    return ellipsis
  }
}
