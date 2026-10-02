import SwiftUI
import AppKit

/// 毛玻璃背景。
///
/// 关键点：圆角用 NSVisualEffectView 自己的 `maskImage` 来裁，而不是依赖 SwiftUI 的
/// `clipShape` —— 后者作用不到 NSViewRepresentable 底下的真实图层，于是模糊层会以
/// 矩形露出来，看起来就是卡片后面多了一块浅色方块。自己裁就干净了。
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var alpha: Double
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = CGFloat(max(0.05, min(1.0, alpha)))
        view.maskImage = Self.roundedMask(radius: cornerRadius)
    }

    /// 可拉伸的圆角遮罩：中间 1pt 用来拉伸，四角保留真实圆角。
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let r = max(0, radius)
        let edge = max(2, r + 1)
        let size = NSSize(width: edge * 2 + 1, height: edge * 2 + 1)

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: edge, left: edge, bottom: edge, right: edge)
        image.resizingMode = .stretch
        return image
    }
}
