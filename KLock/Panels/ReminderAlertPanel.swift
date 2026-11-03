import AppKit
import SwiftUI

/// 允许非激活面板接收 Escape，避免提醒只能依赖鼠标关闭。
private final class ReminderOverlayWindow: NSPanel {
  var onEscape: (() -> Void)?

  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onEscape?()
    } else {
      super.keyDown(with: event)
    }
  }
}

/// 透明度从上到下增加的实时毛玻璃，不需要屏幕录制权限。
private final class ReminderGlassView: NSVisualEffectView {
  private let fadeMask = CAGradientLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    Glass.configureMaterial(self)
    wantsLayer = true
    fadeMask.startPoint = CGPoint(x: 0.5, y: 1)
    fadeMask.endPoint = CGPoint(x: 0.5, y: 0)
    fadeMask.colors = [
      NSColor.clear.cgColor,
      NSColor.clear.cgColor,
      NSColor.white.withAlphaComponent(0.7).cgColor,
      NSColor.white.cgColor,
    ]
    fadeMask.locations = [0, 0.25, 0.70, 1]
    layer?.mask = fadeMask
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    fadeMask.frame = bounds
  }
}

/// 计时结束后在屏幕下半部显示渐变毛玻璃和可操作的提醒。
class ReminderAlertPanel {
  private var panel: ReminderOverlayWindow?
  private var backdropPanel: NSPanel?
  private var onClose: (() -> Void)?
  private var onTimeout: (() -> Void)?
  private var onSnooze: ((Int) -> Void)?
  private var onPause: (() -> Void)?
  private var onDelete: (() -> Void)?
  private var screenChangeObserver: NSObjectProtocol?
  private var autoDismissTimer: Timer?

  private static let autoDismissInterval: TimeInterval = 30

  deinit {
    cleanup()
  }

  func show(
    timerName: String,
    detail: String,
    onClose: @escaping () -> Void,
    onTimeout: @escaping () -> Void,
    onSnooze: @escaping (Int) -> Void,
    onPause: @escaping () -> Void,
    onDelete: @escaping () -> Void
  ) {
    cleanup()
    self.onClose = onClose
    self.onTimeout = onTimeout
    self.onSnooze = onSnooze
    self.onPause = onPause
    self.onDelete = onDelete

    let screen = ScreenPlacement.screenForMouse()
    // 暂时没有显示器时保留窗口，显示器重新连接后再由通知调整尺寸。
    let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
    let dismissAt = Date().addingTimeInterval(Self.autoDismissInterval)

    let content = ReminderAlertView(
      timerName: timerName,
      detail: detail,
      dismissAt: dismissAt,
      dismissInterval: Self.autoDismissInterval,
      onClose: { [weak self] in self?.handleClose() },
      onSnooze: { [weak self] minutes in self?.handleSnooze(minutes: minutes) },
      onPause: { [weak self] in self?.handlePause() },
      onDelete: { [weak self] in self?.handleDelete() }
    )
    .environment(\.colorScheme, .dark)

    // 背景和操作区使用独立窗口：渐变不会挡住下方应用的鼠标操作。
    let backdrop = NSPanel(
      contentRect: Self.backdropFrame(in: screenFrame),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    backdrop.isReleasedWhenClosed = false
    backdrop.isFloatingPanel = true
    backdrop.hidesOnDeactivate = false
    backdrop.level = .screenSaver
    backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    backdrop.isOpaque = false
    backdrop.backgroundColor = .clear
    backdrop.hasShadow = false
    backdrop.ignoresMouseEvents = true
    backdrop.appearance = NSAppearance(named: .darkAqua)

    let glass = ReminderGlassView(frame: NSRect(origin: .zero, size: backdrop.frame.size))
    glass.autoresizingMask = [.width, .height]
    backdrop.contentView?.addSubview(glass)

    let gradient = NSHostingView(rootView: ReminderBackdropView())
    gradient.frame = glass.bounds
    gradient.autoresizingMask = [.width, .height]
    backdrop.contentView?.addSubview(gradient)

    let panel = ReminderOverlayWindow(
      contentRect: Self.contentFrame(in: screenFrame),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.level = .screenSaver
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovableByWindowBackground = false
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.onEscape = { [weak self] in self?.handleClose() }

    let host = NSHostingView(rootView: content)
    host.frame = NSRect(origin: .zero, size: panel.frame.size)
    host.autoresizingMask = [.width, .height]
    panel.contentView?.addSubview(host)

    self.panel = panel
    self.backdropPanel = backdrop
    screenChangeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      self?.fitToCurrentScreen()
    }
    backdrop.orderFrontRegardless()
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(nil)

    let timer = Timer(fire: dismissAt, interval: 0, repeats: false) {
      [weak self] _ in self?.handleTimeout()
    }
    RunLoop.main.add(timer, forMode: .common)
    autoDismissTimer = timer
  }

  private static func backdropFrame(in screen: NSRect) -> NSRect {
    NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height * 0.65)
  }

  private static func contentFrame(in screen: NSRect) -> NSRect {
    let width = max(1, min(520, screen.width - 48))
    let height = max(1, min(230, screen.height - 48))
    let centerY = screen.minY + screen.height * 0.40
    return NSRect(x: screen.midX - width / 2, y: centerY - height / 2, width: width, height: height)
  }

  private func fitToCurrentScreen() {
    guard let panel = panel,
      let screen = backdropPanel?.screen ?? panel.screen ?? ScreenPlacement.screenForMouse()
    else { return }
    backdropPanel?.setFrame(Self.backdropFrame(in: screen.frame), display: true)
    panel.setFrame(Self.contentFrame(in: screen.frame), display: true)
  }

  /// 静默关闭（例如对应计时器被手动删除）。
  func close() {
    cleanup()
  }

  private func handleClose() {
    // 回调里外部会释放本对象，这里先持有强引用，避免方法执行中途被销毁。
    let alive = self
    let action = alive.onClose
    alive.cleanup()
    action?()
    _ = alive
  }

  private func handleSnooze(minutes: Int) {
    let alive = self
    let action = alive.onSnooze
    alive.cleanup()
    action?(minutes)
    _ = alive
  }

  private func handlePause() {
    let alive = self
    let action = alive.onPause
    alive.cleanup()
    action?()
    _ = alive
  }

  private func handleDelete() {
    let alive = self
    let action = alive.onDelete
    alive.cleanup()
    action?()
    _ = alive
  }

  private func handleTimeout() {
    let alive = self
    let action = alive.onTimeout
    alive.cleanup()
    action?()
    _ = alive
  }

  private func cleanup() {
    autoDismissTimer?.invalidate()
    autoDismissTimer = nil
    if let observer = screenChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      screenChangeObserver = nil
    }
    onClose = nil
    onTimeout = nil
    onSnooze = nil
    onPause = nil
    onDelete = nil
    panel?.onEscape = nil
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    backdropPanel?.orderOut(nil)
    backdropPanel?.close()
    backdropPanel = nil
  }
}
