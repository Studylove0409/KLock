import AppKit

/// 记录列表用的容器，让内容从顶部开始排列。
private final class FlippedStackContainer: NSView {
  override var isFlipped: Bool { true }
}

final class HistoryWindowController: NSWindowController {
  static let shared = HistoryWindowController()

  private let rowsStack = NSStackView()
  private let emptyLabel = NSTextField(labelWithString: "还没有记录，拖一次菜单栏图标试试。")
  private var scrollView: NSScrollView?

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "计时历史"
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 380, height: 300)
    super.init(window: window)
    buildUI()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func showWindow() {
    reload()
    // 不用 window.center()：它会按 AppKit 认定的主屏居中，
    // 多显示器下常常弹到另一块屏上。统一跟随鼠标所在屏幕。
    if let window = window {
      let screen = NSScreen.screens.first {
        $0.frame.contains(NSEvent.mouseLocation)
      } ?? NSScreen.main
      if let visible = screen?.visibleFrame {
        let size = window.frame.size
        window.setFrameOrigin(
          NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2))
      }
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  private func buildUI() {
    guard let window = window else { return }

    let background = NSVisualEffectView()
    background.material = .sidebar
    background.blendingMode = .behindWindow
    background.state = .active
    background.translatesAutoresizingMaskIntoConstraints = false

    let clearButton = NSButton(
      title: "清空", target: self, action: #selector(clearHistory))
    clearButton.bezelStyle = .inline
    clearButton.isBordered = false
    clearButton.contentTintColor = .secondaryLabelColor
    clearButton.font = NSFont.systemFont(ofSize: 12)

    // 窗口标题栏已经写了「计时历史」，这里只放操作按钮，避免重复标题
    let header = NSStackView(views: [NSView(), clearButton])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    header.translatesAutoresizingMaskIntoConstraints = false

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scrollView = scroll

    let document = FlippedStackContainer()
    document.translatesAutoresizingMaskIntoConstraints = false

    rowsStack.orientation = .vertical
    rowsStack.alignment = .leading
    rowsStack.spacing = 0
    rowsStack.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(rowsStack)
    scroll.documentView = document

    emptyLabel.font = NSFont.systemFont(ofSize: 12)
    emptyLabel.textColor = .secondaryLabelColor
    emptyLabel.alignment = .center
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false

    background.addSubview(header)
    background.addSubview(scroll)
    background.addSubview(emptyLabel)
    window.contentView = background

    NSLayoutConstraint.activate([
      background.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      background.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      background.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      background.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),

      header.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
      header.leadingAnchor.constraint(equalTo: background.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: background.trailingAnchor),
      header.heightAnchor.constraint(equalToConstant: 24),

      scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
      scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),

      document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
      document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
      document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

      rowsStack.topAnchor.constraint(equalTo: document.topAnchor),
      rowsStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
      rowsStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
      rowsStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),

      emptyLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: background.centerYAnchor),
    ])
  }

  private func reload() {
    rowsStack.arrangedSubviews.forEach {
      rowsStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }

    let records = HistoryStore.shared.records
    emptyLabel.isHidden = !records.isEmpty

    var currentDay: String?
    var indexInGroup = 0

    for record in records {
      let moment = record.finishedAt ?? record.createdAt
      let day = Self.dayText(moment)

      if day != currentDay {
        currentDay = day
        indexInGroup = 0
        let header = makeSectionHeader(day)
        rowsStack.addArrangedSubview(header)
        NSLayoutConstraint.activate([
          header.widthAnchor.constraint(equalTo: rowsStack.widthAnchor),
          header.heightAnchor.constraint(equalToConstant: 30),
        ])
      } else if indexInGroup > 0 {
        let line = makeSeparator()
        rowsStack.addArrangedSubview(line)
        NSLayoutConstraint.activate([
          line.heightAnchor.constraint(equalToConstant: 1),
          line.widthAnchor.constraint(
            equalTo: rowsStack.widthAnchor, constant: -40),
        ])
      }

      let row = makeRow(for: record)
      rowsStack.addArrangedSubview(row)
      NSLayoutConstraint.activate([
        row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor),
        row.heightAnchor.constraint(equalToConstant: 44),
      ])
      indexInGroup += 1
    }
  }

  /// 日期分组标题（今天 / 昨天 / 11月1日）
  private func makeSectionHeader(_ text: String) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    let row = NSStackView(views: [label])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 2, right: 20)
    return row
  }

  private func makeRow(for record: TimerRecord) -> NSView {
    let nameLabel = NSTextField(labelWithString: record.name)
    nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    nameLabel.textColor = .labelColor
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let statusLabel = NSTextField(labelWithString: record.status.label)
    statusLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    statusLabel.textColor = Self.statusColor(record.status)
    statusLabel.alignment = .right
    statusLabel.setContentHuggingPriority(.required, for: .horizontal)

    let moment = record.finishedAt ?? record.createdAt
    let metaLabel = NSTextField(
      labelWithString:
        "\(Self.durationText(record.duration))  ·  \(Self.dateText(moment))"
    )
    metaLabel.font = NSFont.monospacedDigitSystemFont(
      ofSize: 11, weight: .regular)
    metaLabel.textColor = .secondaryLabelColor
    metaLabel.alignment = .right
    metaLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    let row = NSStackView(views: [nameLabel, statusLabel, metaLabel])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10
    // .gravityAreas（默认）会把多余空间留在尾部，右侧时间就贴不到右边
    row.distribution = .fill
    row.edgeInsets = NSEdgeInsets(top: 11, left: 20, bottom: 11, right: 20)
    return row
  }

  private static func statusColor(_ status: TimerRecordStatus) -> NSColor {
    switch status {
    case .active: return .controlAccentColor
    case .finished: return .secondaryLabelColor
    case .cancelled: return .tertiaryLabelColor
    }
  }

  private func makeSeparator() -> NSView {
    let line = NSBox()
    line.boxType = .separator
    line.translatesAutoresizingMaskIntoConstraints = false
    return line
  }

  private static func durationText(_ duration: TimeInterval) -> String {
    let seconds = Int(duration)
    if seconds < 60 {
      return "\(seconds) 秒"
    }
    let minutes = seconds / 60
    if minutes < 60 {
      return "\(minutes) 分钟"
    }
    let hours = minutes / 60
    let restMinutes = minutes % 60
    return restMinutes == 0
      ? "\(hours) 小时" : "\(hours) 小时 \(restMinutes) 分"
  }

  // 复用一个 formatter：每次新建在 200 条记录时要建 200 个
  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static let stampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter
  }()

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter
  }()

  private static func dayText(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "今天" }
    if calendar.isDateInYesterday(date) { return "昨天" }
    return dayFormatter.string(from: date)
  }

  private static func dateText(_ date: Date) -> String {
    Calendar.current.isDateInToday(date)
      ? timeFormatter.string(from: date)
      : stampFormatter.string(from: date)
  }

  @objc private func clearHistory() {
    let count = HistoryStore.shared.records.count
    guard count > 0, let window = window else { return }

    let alert = NSAlert()
    alert.messageText = "清空全部历史记录？"
    alert.informativeText = "共 \(count) 条，清空后无法恢复。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "清空")
    alert.addButton(withTitle: "取消")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      HistoryStore.shared.clear()
      self?.reload()
    }
  }
}
