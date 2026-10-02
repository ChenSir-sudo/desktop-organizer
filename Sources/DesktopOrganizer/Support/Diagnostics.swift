import AppKit

/// 自检工具：在无人值守的情况下确认窗口真的被创建、几何计算是否正确、拖拽通道是否挂上。
///
/// 用法（环境变量）：
///   DO_DIAG=<输出文件>        写一份当前窗口状态快照
///   DO_DIAG_SETTINGS=1        顺便展开第一个整理框的设置面板，验证展开/收起几何
///   DO_DIAG_UNPIN=1           把第一个整理框改成「不置顶」，用于对比窗口层级
enum Diagnostics {

    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["DO_DIAG"] else { return }
        let environment = ProcessInfo.processInfo.environment

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if environment["DO_DIAG_UNPIN"] != nil, let first = Store.shared.boxes.first {
                Store.shared.update(id: first.id) { $0.floatOnTop = false }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            var output = snapshot("初始状态")

            guard environment["DO_DIAG_SETTINGS"] != nil,
                  let first = Store.shared.boxes.first else {
                try? output.write(toFile: path, atomically: true, encoding: .utf8)
                return
            }

            BoxWindowManager.shared.controller(for: first.id)?.toggleSettingsPanel()
            output += "\n\n" + snapshot("展开设置面板后（预期高度 +322，顶边不动）")

            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                var final = output
                BoxWindowManager.shared.controller(for: first.id)?.toggleSettingsPanel()
                final += "\n\n" + snapshot("收起设置面板后（预期高度还原）")
                final += "\n\n持久化帧: " + NSStringFromRect(Store.shared.boxes.first?.frame ?? .zero)
                try? final.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func snapshot(_ title: String) -> String {
        var lines: [String] = ["## \(title)"]
        lines.append("boxes=\(Store.shared.boxes.count) controllers=\(BoxWindowManager.shared.count)")
        for box in Store.shared.boxes {
            lines.append("  model name=\(box.name) floatOnTop=\(box.floatOnTop)"
                + " material=\(box.material.rawValue) opacity=\(box.opacity)")
        }
        lines.append("activationPolicy=\(NSApp.activationPolicy().rawValue) isActive=\(NSApp.isActive)")
        let screens = NSScreen.screens
        lines.append("screens=" + screens.map { NSStringFromRect($0.frame) }.joined(separator: " | "))
        lines.append("visibleFrames=" + screens.map { NSStringFromRect($0.visibleFrame) }.joined(separator: " | "))

        for window in NSApp.windows {
            let kind = String(describing: type(of: window))
            let contentFrame = window.contentView.map { NSStringFromRect($0.frame) } ?? "nil"
            let fitting = window.contentView.map { NSStringFromSize($0.fittingSize) } ?? "nil"
            lines.append("  [\(kind)] visible=\(window.isVisible) frame=\(NSStringFromRect(window.frame))"
                + " level=\(window.level.rawValue) content=\(contentFrame) fitting=\(fitting)")
            appendDragTargets(window.contentView, depth: 2, into: &lines)
        }
        return lines.joined(separator: "\n")
    }

    /// 把视图树里注册了拖拽类型的节点列出来，确认「拖文件进框」的通道确实挂上了。
    private static func appendDragTargets(_ view: NSView?, depth: Int, into lines: inout [String]) {
        guard let view, depth >= 0 else { return }
        let types = view.registeredDraggedTypes.map(\.rawValue).sorted()
        if !types.isEmpty {
            lines.append("      drag-target \(type(of: view)) -> \(types)")
        }
        for subview in view.subviews {
            appendDragTargets(subview, depth: depth - 1, into: &lines)
        }
    }
}
