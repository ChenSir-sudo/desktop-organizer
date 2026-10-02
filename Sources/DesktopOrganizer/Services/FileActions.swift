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
