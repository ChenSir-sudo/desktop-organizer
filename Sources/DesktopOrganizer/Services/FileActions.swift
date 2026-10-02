import AppKit

/// 对条目能做的操作。全部是只读或用户显式确认后才执行的，绝不隐式搬移文件。
enum FileActions {

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealParentFolder(of url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
    }

    /// 移到废纸篓 —— 这是整个程序里唯一会动文件的地方，且必须由用户逐个触发并二次确认。
    @discardableResult
    static func moveToTrash(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            return false
        }
    }

    /// 用已安装的代码编辑器打开。找不到就退回系统默认方式。
    static func openInCodeEditor(_ url: URL) {
        let candidates = ["Visual Studio Code", "Cursor", "Windsurf", "Zed", "Sublime Text"]
        for name in candidates {
            let appURL = URL(fileURLWithPath: "/Applications/\(name).app")
            guard FileManager.default.fileExists(atPath: appURL.path) else { continue }
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 在终端里打开所在目录（优先 iTerm，其次系统终端）。
    static func openInTerminal(_ url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let directory = isDirectory.boolValue ? url : url.deletingLastPathComponent()

        let iTerm = URL(fileURLWithPath: "/Applications/iTerm.app")
        let terminal = FileManager.default.fileExists(atPath: iTerm.path)
            ? iTerm
            : URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    struct MoveOutcome {
        var moved: [URL] = []
        var failures: [(url: URL, reason: String)] = []
    }

    /// 把文件移进某个文件夹。
    /// 只有用户明确把文件拖到某个文件夹图标上才会走到这里 —— 这是显式意图，
    /// 但仍然拒绝受保护路径，并且不覆盖同名文件。
    static func move(_ urls: [URL], into folder: URL) -> MoveOutcome {
        let fm = FileManager.default
        var outcome = MoveOutcome()
        let destinationRoot = folder.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destinationRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            outcome.failures = urls.map { ($0, "目标不是文件夹") }
            return outcome
        }

        for source in urls {
            let src = source.standardizedFileURL
            guard fm.fileExists(atPath: src.path) else {
                outcome.failures.append((src, "文件不存在")); continue
            }
            if src.deletingLastPathComponent().path == destinationRoot.path { continue }   // 已经在里面
            if destinationRoot.path.hasPrefix(src.path + "/") {
                outcome.failures.append((src, "不能把文件夹移进它自己")); continue
            }
            if BoxConfig.isProtected(src) {
                outcome.failures.append((src, "受保护的路径")); continue
            }

            let destination = uniqueDestination(for: src, in: destinationRoot)
            do {
                try fm.moveItem(at: src, to: destination)
                outcome.moved.append(destination)
            } catch {
                // 跨宗卷时退化成复制 + 删除
                do {
                    try fm.copyItem(at: src, to: destination)
                    try fm.removeItem(at: src)
                    outcome.moved.append(destination)
                } catch {
                    outcome.failures.append((src, error.localizedDescription))
                }
            }
        }
        return outcome
    }

    /// 同名文件自动加序号，绝不覆盖。
    private static func uniqueDestination(for source: URL, in folder: URL) -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        fm.fileExists(atPath: source.path, isDirectory: &isDirectory)

        let name = source.lastPathComponent
        var candidate = folder.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let base: String
        let ext: String
        if isDirectory.boolValue {
            base = name; ext = ""
        } else {
            base = (name as NSString).deletingPathExtension
            ext = (name as NSString).pathExtension
        }
        var counter = 2
        while counter < 9999 {
            let next = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(next)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
        return folder.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    static func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    /// 打开「选择文件」面板，用来手动往整理框里加引用。
    static func pickFiles(message: String, startingAt: URL?) -> [URL] {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        panel.message = message
        panel.directoryURL = startingAt ?? AppPaths.desktopDirectory
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func info(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
