import EventKit
import SwiftUI

class PreferencesWindowController: NSWindowController {
  static let shared = PreferencesWindowController()

  private var hasBeenPositioned = false

  private init() {
    let preferencesView = PreferencesView()
    let hostingController = NSHostingController(rootView: preferencesView)

    let window = NSWindow(contentViewController: hostingController)
    window.title = "KLock 偏好设置"
    window.setContentSize(NSSize(width: 720, height: 540))
    window.minSize = NSSize(width: 700, height: 480)

    // 让毛玻璃铺满整窗，标题栏透明，红绿灯直接压在侧栏上——
    // 这是系统设置的观感，而不是「灰底 + 标题栏」的普通窗口。
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.backgroundColor = .clear
    window.isOpaque = false
    window.isReleasedWhenClosed = false
    window.level = .floating

    super.init(window: window)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func showWindow() {
    if let window = window {
      // 只有第一次、或窗口已经不在任何屏幕上时才居中；
      // 用户拖到哪儿就记住哪儿，不要每次打开都跳回屏幕中间。
      let isOnScreen = NSScreen.screens.contains {
        $0.visibleFrame.intersects(window.frame)
      }
      if !hasBeenPositioned || !isOnScreen {
        hasBeenPositioned = true
        let screen = ScreenPlacement.screenForMouse()
        if let visible = screen?.visibleFrame {
          let size = window.frame.size
          window.setFrameOrigin(
            NSPoint(
              x: visible.midX - size.width / 2,
              y: visible.midY - size.height / 2))
        }
      }
      window.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
  }
}
