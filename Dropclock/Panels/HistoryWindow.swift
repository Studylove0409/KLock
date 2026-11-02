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
    window?.center()
    window?.makeKeyAndOrderFront(nil)
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

    for (index, record) in records.enumerated() {
      if index > 0 {
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
    }
  }

  private func makeRow(for record: TimerRecord) -> NSView {
    let nameLabel = NSTextField(labelWithString: record.name)
    nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    nameLabel.textColor = .labelColor
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let metaLabel = NSTextField(
      labelWithString:
        "\(Self.durationText(record.duration))  ·  \(Self.dateText(record.finishedAt))"
    )
    metaLabel.font = NSFont.monospacedDigitSystemFont(
      ofSize: 11, weight: .regular)
    metaLabel.textColor = .secondaryLabelColor
    metaLabel.alignment = .right
    metaLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    let row = NSStackView(views: [nameLabel, metaLabel])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.edgeInsets = NSEdgeInsets(top: 11, left: 20, bottom: 11, right: 20)
    return row
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

  private static func dateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
  }

  @objc private func clearHistory() {
    HistoryStore.shared.clear()
    reload()
  }
}
