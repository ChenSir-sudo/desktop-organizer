import AppKit

/// 对齐引导线的方向。
enum SnapAxis {
    case vertical     // 竖线，约束 x
    case horizontal   // 横线，约束 y
}

struct GuideLine {
    var axis: SnapAxis
    var position: CGFloat
    var from: CGFloat
    var to: CGFloat
}

struct SnapResult {
    var origin: CGPoint
    var guides: [GuideLine]
}

/// 拖动窗口时的吸附计算：屏幕边/中线，以及其它整理框的边/中线。
enum SnapEngine {
    static let threshold: CGFloat = 8

    static func snap(moving: CGRect, others: [CGRect], screen: CGRect) -> SnapResult {
        var xTargets: [CGFloat] = [screen.minX, screen.midX, screen.maxX]
        var yTargets: [CGFloat] = [screen.minY, screen.midY, screen.maxY]
        for other in others {
            xTargets.append(contentsOf: [other.minX, other.midX, other.maxX])
            yTargets.append(contentsOf: [other.minY, other.midY, other.maxY])
        }
        // 屏幕边角离得太远时不显示引导线
        xTargets = xTargets.filter { abs($0 - moving.midX) < 900 }
        yTargets = yTargets.filter { abs($0 - moving.midY) < 900 }

        let xEdges: [CGFloat] = [moving.minX, moving.midX, moving.maxX]
        let yEdges: [CGFloat] = [moving.minY, moving.midY, moving.maxY]

        var bestX: (delta: CGFloat, line: CGFloat, distance: CGFloat)?
        for edge in xEdges {
            for target in xTargets {
                let delta = target - edge
                guard abs(delta) <= threshold else { continue }
                if bestX == nil || abs(delta) < bestX!.distance {
                    bestX = (delta, target, abs(delta))
                }
            }
        }

        var bestY: (delta: CGFloat, line: CGFloat, distance: CGFloat)?
        for edge in yEdges {
            for target in yTargets {
                let delta = target - edge
                guard abs(delta) <= threshold else { continue }
                if bestY == nil || abs(delta) < bestY!.distance {
                    bestY = (delta, target, abs(delta))
                }
            }
        }

        var origin = moving.origin
        var guides: [GuideLine] = []

        if let x = bestX {
            origin.x += x.delta
            guides.append(GuideLine(axis: .vertical, position: x.line, from: screen.minY, to: screen.maxY))
        }
        if let y = bestY {
            origin.y += y.delta
            guides.append(GuideLine(axis: .horizontal, position: y.line, from: screen.minX, to: screen.maxX))
        }

        return SnapResult(origin: origin, guides: guides)
    }
}

// MARK: - 引导线浮层

/// 一条覆盖整屏、不吃鼠标事件的透明窗口，用来画对齐引导线。
final class GuideOverlayWindow: NSWindow {

    private let guideView = GuideContentView()

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = guideView
    }

    func show(guides: [GuideLine], on screen: NSScreen) {
        guard !guides.isEmpty else { hide(); return }
        setFrame(screen.frame, display: false)
        guideView.frame = CGRect(origin: .zero, size: screen.frame.size)
        guideView.guides = guides
        orderFrontRegardless()
    }

    func hide() {
        guideView.guides = []
        orderOut(nil)
    }
}

private final class GuideContentView: NSView {
    var guides: [GuideLine] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !guides.isEmpty, let window else { return }
        let baseX = window.frame.minX
        let baseY = window.frame.minY

        let color = NSColor.controlAccentColor.withAlphaComponent(0.85)
        color.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1
        for guide in guides {
            switch guide.axis {
            case .vertical:
                let x = round(guide.position - baseX) + 0.5
                path.move(to: NSPoint(x: x, y: guide.from - baseY))
                path.line(to: NSPoint(x: x, y: guide.to - baseY))
            case .horizontal:
                let y = round(guide.position - baseY) + 0.5
                path.move(to: NSPoint(x: guide.from - baseX, y: y))
                path.line(to: NSPoint(x: guide.to - baseX, y: y))
            }
        }
        path.stroke()

        // 吸附时在线端点一个小方块，让反馈更明确
        color.withAlphaComponent(0.9).setFill()
        for guide in guides {
            let size: CGFloat = 5
            switch guide.axis {
            case .vertical:
                let x = round(guide.position - baseX) + 0.5 - size / 2
                let rect = NSRect(x: x, y: guide.to - baseY - size, width: size, height: size)
                NSBezierPath(rect: rect).fill()
            case .horizontal:
                let y = round(guide.position - baseY) + 0.5 - size / 2
                let rect = NSRect(x: guide.to - baseX - size, y: y, width: size, height: size)
                NSBezierPath(rect: rect).fill()
            }
        }
    }
}
