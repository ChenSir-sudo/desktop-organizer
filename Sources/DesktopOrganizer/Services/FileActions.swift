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
