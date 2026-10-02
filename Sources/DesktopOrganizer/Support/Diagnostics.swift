import AppKit

/// 自检工具：无人值守时确认窗口真的创建、几何是否正确、拖拽通道是否挂上。
///
///   DO_DIAG=<输出文件>   写一份窗口状态快照
///   DO_DIAG_PAGE=1       顺便把第一个整理框切到设置页，验证整页切换
enum Diagnostics {

    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["DO_DIAG"] else { return }
        let environment = ProcessInfo.processInfo.environment

        // 把指定路径加进第一个整理框，用来端到端验证「原位置隐藏」
        if let addPath = environment["DO_DIAG_ADD"], let first = Store.shared.boxes.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let n = Store.shared.addItems([URL(fileURLWithPath: addPath)], to: first.id)
                try? "added=\(n) hidden=\(HiddenFlag.isHidden(URL(fileURLWithPath: addPath)))"
                    .write(toFile: path + ".add", atomically: true, encoding: .utf8)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            var output = snapshot("初始状态")

            guard environment["DO_DIAG_PAGE"] != nil,
                  let first = Store.shared.boxes.first,
                  let controller = BoxWindowManager.shared.controller(for: first.id) else {
                try? output.write(toFile: path, atomically: true, encoding: .utf8)
                return
            }

            controller.ui.page = .settings
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                output += "\n\n" + snapshot("切到设置页后（窗口尺寸应保持不变）")
                try? output.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func snapshot(_ title: String) -> String {
        var lines: [String] = ["## \(title)"]
        lines.append("boxes=\(Store.shared.boxes.count) controllers=\(BoxWindowManager.shared.count)")
        for box in Store.shared.boxes {
            lines.append("  model name=\(box.name) items=\(box.items.count)"
                + " floatOnTop=\(box.floatOnTop) material=\(box.material.rawValue)"
                + " opacity=\(String(format: "%.2f", box.opacity))")
        }
        lines.append("activationPolicy=\(NSApp.activationPolicy().rawValue) isActive=\(NSApp.isActive)")
        let screens = NSScreen.screens
        lines.append("screens=" + screens.map { NSStringFromRect($0.frame) }.joined(separator: " | "))
        lines.append("visibleFrames=" + screens.map { NSStringFromRect($0.visibleFrame) }.joined(separator: " | "))

        for window in NSApp.windows {
            let kind = String(describing: type(of: window))
            let contentFrame = window.contentView.map { NSStringFromRect($0.frame) } ?? "nil"
            let fitting = window.contentView.map { NSStringFromSize($0.fittingSize) } ?? "nil"
            lines.append("  [\(kind)] title=\(window.title) visible=\(window.isVisible)"
                + " frame=\(NSStringFromRect(window.frame)) level=\(window.level.rawValue)"
                + " content=\(contentFrame) fitting=\(fitting)")
            appendDragTargets(window.contentView, depth: 2, into: &lines)
        }
        return lines.joined(separator: "\n")
    }

    /// 列出视图树里注册了拖拽类型的节点，确认「拖文件进框」的通道确实挂上了。
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
