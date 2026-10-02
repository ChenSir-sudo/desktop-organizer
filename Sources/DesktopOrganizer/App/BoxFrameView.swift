import AppKit

/// 整理框的窗口内容视图 —— **只画一圈边框和标题，中间完全透明**。
///
/// 这是新方案的核心：框不再是"装着文件的毛玻璃面板"，而是桌面上的一块区域。
/// 文件照旧留在 `~/Desktop/xxx`、照旧可见，程序只负责摆它们的图标坐标。
///
/// 关键在 `hitTest`：只有**边框那一圈**和标题接受鼠标，中间一律放行 ——
/// 这样用户仍然可以在框内正常拖动、双击、右键桌面图标。
final class BoxFrameView: NSView {

    /// 边框的感应宽度（点）。小于这个宽度的边缘算"框边"，可以抓着拖动/缩放。
    static let edgeGrip: CGFloat = 14

    /// 所属控制器。边框上的按下事件交给它处理拖动/缩放。
    weak var controller: BoxWindowController?

    var title: String = "" { didSet { needsDisplay = true } }
    var accent: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var isSelected: Bool = false { didSet { needsDisplay = true } }
    /// 框里当前有多少个图标（显示在标题后面）
    var memberCount: Int = 0 { didSet { needsDisplay = true } }

    // MARK: 命中测试 —— 只有边框那一圈吃鼠标

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 中间完全放行给下面的桌面，用户照样能操作图标
        return isOnBorder(point) ? self : nil
    }

    /// 这个点是不是落在"框边"上（含四角）。
    private func isOnBorder(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        let inner = bounds.insetBy(dx: Self.edgeGrip, dy: Self.edgeGrip)
        return !inner.contains(point)
    }

    /// 光标形状：边框上显示可拖动/可缩放
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        let grip = Self.edgeGrip
        addCursorRect(NSRect(x: 0, y: 0, width: grip, height: grip), cursor: .crosshair)
        addCursorRect(NSRect(x: bounds.maxX - grip, y: 0, width: grip, height: grip), cursor: .crosshair)
        addCursorRect(NSRect(x: 0, y: bounds.maxY - grip, width: grip, height: grip), cursor: .crosshair)
        addCursorRect(NSRect(x: bounds.maxX - grip, y: bounds.maxY - grip, width: grip, height: grip), cursor: .crosshair)
    }

    // MARK: 鼠标 —— 只有边框会走到这里（中间被 hitTest 放行了）

    override func mouseDown(with event: NSEvent) {
        controller?.beginInteraction(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        // 跟随由控制器里的定时器负责，这里不用做事
    }

    override func mouseUp(with event: NSEvent) {
        // 同理，定时器检测到松开会收尾
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 18

        // 极淡的底，让区域"看得出来"，但绝不挡住桌面图标
        let fill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: radius, yRadius: radius)
        accent.withAlphaComponent(isSelected ? 0.10 : 0.05).setFill()
        fill.fill()

        // 边框
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
                                  xRadius: radius, yRadius: radius)
        border.lineWidth = isSelected ? 2.5 : 1.5
        (isSelected ? accent : accent.withAlphaComponent(0.55)).setStroke()
        border.stroke()

        drawTitle()
    }

    private func drawTitle() {
        let text = memberCount > 0 ? "\(title)  ·  \(memberCount)" : title
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let padding: CGFloat = 8
        let box = NSRect(x: 10, y: bounds.maxY - size.height - padding * 2 - 4,
                         width: size.width + padding * 2, height: size.height + padding)
        // isFlipped = false，所以 y 从下往上算；标签贴在框顶内侧

        let pill = NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2)
        accent.withAlphaComponent(0.92).setFill()
        pill.fill()
        string.draw(at: NSPoint(x: box.minX + padding, y: box.minY + padding / 2))
    }
}
