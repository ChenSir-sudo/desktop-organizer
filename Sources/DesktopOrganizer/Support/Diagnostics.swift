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

        // 每隔 1.5 秒记录一次「谁拿到了键盘焦点」，用来验证点击是否真的落到整理框上
        if let keyPath = environment["DO_DIAG_KEY"] {
            var lines: [String] = []
            for step in 0..<10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 1.5) {
                    let key: String
                    if let window = NSApp.keyWindow {
                        let kind = String(describing: type(of: window))
                        key = "\(kind) \(NSStringFromRect(window.frame))"
                    } else {
                        key = "nil"
                    }
                    lines.append("t=\(Double(step) * 1.5)s active=\(NSApp.isActive) key=\(key)")
                    try? lines.joined(separator: "\n").write(toFile: keyPath, atomically: true, encoding: .utf8)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            var output = snapshot("初始状态")
            if environment["DO_DIAG_WINDOWS"] != nil {
                output += "\n\n## 窗口前后顺序（0 在最前）\n" + dumpWindowOrder()
            }

            // 验证「把被盖住的整理框叫到前面」
            if environment["DO_DIAG_SUMMON"] != nil, let first = Store.shared.boxes.first {
                BoxWindowManager.shared.controller(for: first.id)?.summon()
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                    var after = "\n\n## summon 4.5s 后（应已落回桌面层）\n"
                    for window in NSApp.windows where window is BoxPanel {
                        after += "  BoxPanel level=\(window.level.rawValue) visible=\(window.isVisible)\n"
                    }
                    after += "\n## summon 之后的窗口顺序\n" + dumpWindowOrder()
                    after += "\n\n## summon 0.8s 后的面板层级\n"
                    for window in NSApp.windows {
                        after += "  \(type(of: window)) level=\(window.level.rawValue)"
                            + " visible=\(window.isVisible) frame=\(NSStringFromRect(window.frame))\n"
                    }
                    try? (output + after).write(toFile: path, atomically: true, encoding: .utf8)
                }
                return
            }

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

    /// 转储屏幕上所有窗口的前后顺序（front-to-back），用来判断我们的窗口
    /// 是不是被别人的窗口压在下面 —— 压住了就点不中。
    static func dumpWindowOrder() -> String {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return "（拿不到窗口列表）" }
        var lines: [String] = []
        for (index, info) in list.prefix(24).enumerated() {
            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            let name = info[kCGWindowName as String] as? String ?? ""
            let level = info[kCGWindowLayer as String] as? Int ?? 0
            var bounds = "?"
            if let dict = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) {
                bounds = NSStringFromRect(rect)
            }
            lines.append("  \(index). [\(level)] \(owner) \(name.isEmpty ? "" : "\"\(name)\"") \(bounds)")
        }
        return lines.joined(separator: "\n")
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
            appendDragTargets(window.contentView, depth: 6, into: &lines)
        }
        return lines.joined(separator: "\n")
    }

    /// 列出视图树里注册了拖拽类型的节点，确认「拖文件进框」的通道确实挂上了。
    private static func appendDragTargets(_ view: NSView?, depth: Int, into lines: inout [String]) {
        appendDragTargets(view, depth: depth, indent: "      ", into: &lines)
    }

    private static func appendDragTargets(_ view: NSView?, depth: Int, indent: String,
                                          into lines: inout [String]) {
        guard let view, depth >= 0 else { return }
        let types = view.registeredDraggedTypes.map(\.rawValue).sorted()
        let name = String(describing: type(of: view))
        if !types.isEmpty {
            lines.append("\(indent)\(name) -> \(types)")
        } else if depth >= 4 {
            lines.append("\(indent)\(name) （未注册）")
        }
        for subview in view.subviews {
            appendDragTargets(subview, depth: depth - 1, indent: indent + "  ", into: &lines)
        }
    }
}
