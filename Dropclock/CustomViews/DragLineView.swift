import AppKit

/// 拖拽时从菜单栏图标拉到鼠标位置的「拉绳」。
///
/// 用 CAShapeLayer 绘制而不是 `draw(_:)`：拖动过程中每帧只更新一条路径，
/// 原来每次 `needsDisplay` 都要重绘整块全屏视图（2560×1440）。
class DragLineView: NSView {
  var startPoint: NSPoint = .zero
  var endPoint: NSPoint = .zero

  private let glowLayer = CAShapeLayer()
  private let outerGlowLayer = CAShapeLayer()
  private let lineLayer = CAShapeLayer()
  private let haloLayer = CAShapeLayer()
  private let dotLayer = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupLayers()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupLayers() {
    wantsLayer = true

    for shape in [outerGlowLayer, glowLayer, lineLayer, haloLayer, dotLayer] {
      shape.fillColor = NSColor.clear.cgColor
      shape.lineCap = .round
      shape.lineJoin = .round
      shape.masksToBounds = false
    }

    outerGlowLayer.lineWidth = 20
    outerGlowLayer.opacity = 0.16

    glowLayer.lineWidth = 8
    glowLayer.opacity = 0.38

    lineLayer.lineWidth = 3

    haloLayer.lineWidth = 0
    dotLayer.lineWidth = 2

    for shape in [outerGlowLayer, glowLayer, lineLayer, haloLayer, dotLayer] {
      layer?.addSublayer(shape)
    }
  }

  /// 跟随系统强调色；用户自定义过颜色则用自定义的。
  private var currentColor: NSColor {
    if UserDefaults.standard.bool(forKey: "changeRubberbandColor"),
      let data = UserDefaults.standard.data(forKey: "dragLineColor"),
      let color = try? NSKeyedUnarchiver.unarchivedObject(
        ofClass: NSColor.self, from: data)
    {
      return color
    }
    return .controlAccentColor
  }

  func update(start: NSPoint, end: NSPoint) {
    startPoint = start
    endPoint = end
    render()
  }

  private func render() {
    let color = currentColor
    let path = linePath(from: startPoint, to: endPoint)

    // 关掉隐式动画，否则拖动时路径会有追帧延迟。
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    lineLayer.path = path
    lineLayer.strokeColor = color.cgColor
    lineLayer.shadowColor = color.cgColor
    lineLayer.shadowOpacity = 0.9
    lineLayer.shadowRadius = 6
    lineLayer.shadowOffset = .zero

    glowLayer.path = path
    glowLayer.strokeColor = color.withAlphaComponent(0.9).cgColor

    outerGlowLayer.path = path
    outerGlowLayer.strokeColor = color.cgColor

    // 鼠标端的光晕，让人感觉绳子「停」在手边
    let haloRadius: CGFloat = 16
    haloLayer.path = CGPath(
      ellipseIn: CGRect(
        x: endPoint.x - haloRadius, y: endPoint.y - haloRadius,
        width: haloRadius * 2, height: haloRadius * 2),
      transform: nil)
    haloLayer.fillColor = color.withAlphaComponent(0.16).cgColor

    let dotRadius: CGFloat = 5
    dotLayer.path = CGPath(
      ellipseIn: CGRect(
        x: endPoint.x - dotRadius, y: endPoint.y - dotRadius,
        width: dotRadius * 2, height: dotRadius * 2),
      transform: nil)
    dotLayer.fillColor = color.cgColor
    dotLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor

    CATransaction.commit()
  }

  /// 微微下垂的二次贝塞尔，像一根被拉起的橡皮筋；拉得越长弧越明显。
  private func linePath(from start: NSPoint, to end: NSPoint) -> CGPath {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    let sag = min(30, length * 0.12)
    let control = NSPoint(
      x: start.x + dx * 0.5,
      y: start.y + dy * 0.5 - sag)

    let path = CGMutablePath()
    path.move(to: start)
    path.addQuadCurve(to: end, control: control)
    return path
  }
}
