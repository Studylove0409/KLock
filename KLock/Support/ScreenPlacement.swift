import AppKit

enum ScreenPlacement {
  static func screenForMouse(fallback: NSScreen? = NSScreen.main) -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? fallback ?? NSScreen.screens.first
  }
}
