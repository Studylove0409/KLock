import AppKit
import SwiftUI

extension AppDelegate {

  internal func setupDrag(for button: NSStatusBarButton) {
    // 拖拽会直接读取 UserDefaults，需在首次拖拽和打开设置之前注册默认值。
    PreferencesViewModel.registerDefaultPreferences()
    let dragRecognizer = NSPanGestureRecognizer(
      target: self, action: #selector(handleDrag(_:)))
    button.addGestureRecognizer(dragRecognizer)
  }

  @objc internal func handleDrag(_ sender: NSPanGestureRecognizer) {
    let translation = sender.translation(in: sender.view)
    let isCtrlKeyPressed = NSEvent.modifierFlags.contains(.control)
    let isShiftKeyPressed = NSEvent.modifierFlags.contains(.shift)

    switch sender.state {
    case .began:
      discardPendingTimerCreation()
      dragTimeInterval = 0
      dragStartLocation = translation
      if UserDefaults.standard.bool(forKey: "showDragIndicator") {
        createDragLine(sender: sender)
      }

    case .changed:
      guard let start = dragStartLocation else { return }
      let deltaX = abs(translation.x - start.x)
      let deltaY = abs(translation.y - start.y)
      let maxDelta = max(deltaX, deltaY)

      // Time Calculation Logic
      var calculatedInterval: TimeInterval = 0
      var continuousInterval: TimeInterval = 0
      var usesSpecialStep = false
      if isCtrlKeyPressed
        && UserDefaults.standard.bool(forKey: "allowFiveMinuteMode")
      {
        usesSpecialStep = true
        if maxDelta >= SecondThreshold {
          let increments = Int((maxDelta - SecondThreshold) / 5) + 1
          calculatedInterval = TimeInterval(increments * 60 * 5)
        } else {
          removeDragTimerPanel()
          calculatedInterval = 0
        }
      } else if isShiftKeyPressed
        && UserDefaults.standard.bool(forKey: "allowSecondsMode")
      {
        usesSpecialStep = true
        if maxDelta >= SecondThreshold {
          let increments = Int(maxDelta - SecondThreshold) + 1
          calculatedInterval = TimeInterval(30 + increments)
        } else {
          removeDragTimerPanel()
          calculatedInterval = 0
        }
      } else {
        if maxDelta < SecondThreshold {
          removeDragTimerPanel()
          calculatedInterval = 0
        } else if maxDelta < ThirtySecondThreshold {
          let increments = Int(maxDelta - SecondThreshold) + 1
          calculatedInterval = TimeInterval(30 + increments)
          continuousInterval = TimeInterval(31 + maxDelta - SecondThreshold)
        } else if maxDelta < MinuteThreshold {
          let increments = Int((maxDelta - ThirtySecondThreshold) / 5)
          calculatedInterval = TimeInterval(60 + increments * 30)
          continuousInterval = TimeInterval(60 + (maxDelta - ThirtySecondThreshold) / 5 * 30)
        } else {
          let increments = Int((maxDelta - MinuteThreshold) / 5)
          calculatedInterval = TimeInterval(300 + increments * 60)
          continuousInterval = TimeInterval(300 + (maxDelta - MinuteThreshold) / 5 * 60)
        }
      }

      // Control / Shift 已有自己的步进，跳过磁吸以免改变它们的精度。
      calculatedInterval = TimerMath.snappedDragDuration(
        stepped: calculatedInterval, continuous: continuousInterval, specialMode: usesSpecialStep)
      dragTimeInterval = calculatedInterval
      // 用「此刻 + 时长」而不是「按下时刻 + 时长」，
      // 因为计时器是在松手后才真正开始的，这样预览的结束时间才和实际一致。
      endTime = Date().addingTimeInterval(dragTimeInterval)

      let displayText: String
      if calculatedInterval < 60 {
        displayText = "\(Int(calculatedInterval)) 秒"
      } else if calculatedInterval < 300 {
        let minutes = Int(calculatedInterval) / 60
        let seconds = Int(calculatedInterval) - minutes * 60
        displayText = "\(minutes) 分 \(seconds) 秒"
      } else {
        if calculatedInterval <= 3600
          || UserDefaults.standard.bool(forKey: "viewAsMinutes")
        {
          let minutes = Int(calculatedInterval) / 60
          displayText = "\(minutes) 分钟"
        } else {
          let hours = Int(calculatedInterval) / 3600
          let minutes = Int(Int(calculatedInterval) - hours * 3600) / 60
          displayText = "\(hours) 小时 \(minutes) 分"
        }
      }

      let mouseLoc = NSEvent.mouseLocation

      if maxDelta >= SecondThreshold && dragTimerPanel == nil {
        createDragTimerPanel()
      }

      if dragTimerPanel != nil {
        let windowWidth = dragTimerPanel!.frame.width
        let adjustedOrigin = NSPoint(
          x: mouseLoc.x - (windowWidth / 2) - 10, y: mouseLoc.y)
        updateDragTimerWindow(
          withText: displayText, endTimeText: formatter.string(from: endTime!),
          atPoint: adjustedOrigin)
      }

      updateDragLine(sender: sender)

    case .ended, .cancelled, .failed:
      removeDragTimerPanel()
      removeDragLine()
      if sender.state == .ended, dragTimeInterval > 0 {
        beginDurationAdjustment(duration: dragTimeInterval, at: NSEvent.mouseLocation)
      }
      dragTimeInterval = 0
      dragStartLocation = nil
      updateStatusIcon()

    default:
      break
    }
  }

  private func createDragLine(sender: NSPanGestureRecognizer) {
    guard let button = sender.view as? NSStatusBarButton,
      let buttonWindow = button.window,
      let screen = buttonWindow.screen ?? NSScreen.main
    else { return }

    let buttonFrame = buttonWindow.frame
    let startPoint = NSPoint(x: buttonFrame.midX, y: buttonFrame.midY)
    let endPoint = NSEvent.mouseLocation

    // 复用同一个覆盖窗口：既避免每次拖拽新建窗口造成泄漏，
    // 也不在拖拽结束时 close()，规避关闭与释放时序导致的崩溃。
    let window: NSWindow
    if let existing = dragLineWindow {
      window = existing
      if window.frame != screen.frame {
        window.setFrame(screen.frame, display: false)
      }
    } else {
      window = NSWindow(
        contentRect: screen.frame, styleMask: .borderless, backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.backgroundColor = .clear
      window.ignoresMouseEvents = true
      window.level = .statusBar
      dragLineWindow = window
    }

    dragLineView?.removeFromSuperview()

    let lineView = DragLineView(frame: screen.frame)
    lineView.startPoint = startPoint
    lineView.endPoint = endPoint
    lineView.wantsLayer = true
    lineView.layer?.zPosition = CGFloat(Float.greatestFiniteMagnitude)

    window.contentView?.addSubview(lineView)
    window.makeKeyAndOrderFront(nil)

    dragLineView = lineView
    lineView.update(start: startPoint, end: endPoint)
  }

  private func updateDragLine(sender: NSPanGestureRecognizer) {
    guard let lineView = dragLineView,
      let button = sender.view as? NSStatusBarButton
    else { return }

    let buttonFrame = button.window!.frame
    let startPoint = NSPoint(x: buttonFrame.midX, y: buttonFrame.midY)
    let endPoint = NSEvent.mouseLocation

    lineView.update(start: startPoint, end: endPoint)
  }

  private func removeDragLine() {
    dragLineView?.removeFromSuperview()
    dragLineView = nil
    // 只隐藏窗口，留待下次拖拽复用；这里不 close，避免释放时序问题。
    dragLineWindow?.orderOut(nil)
  }
}
