import SwiftUI
import AppKit

/// 承载毛玻璃背景。用 AppKit 的 NSVisualEffectView 才能做到「透出桌面壁纸」的真实模糊。
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var alpha: Double

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
    }
}
