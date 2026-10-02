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
        guard !BoxConfig.isProtected(url) else {
            OperationsLog.append("拒绝把受保护路径移到废纸篓: \(url.path)")
            return false
        }
        OperationsLog.append("移到废纸篓: \(url.path)")
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            return false
        }
    }

    /// 已安装的代码编辑器。
    ///
    /// 先按 bundle identifier 找，这样装在 ~/Applications 或别处的也能认出来；
    /// 找不到再退回 /Applications 下的固定路径。
    static func detectedEditors() -> [(name: String, url: URL)] {
        let candidates: [(name: String, bundleID: String)] = [
            ("Visual Studio Code", "com.microsoft.VSCode"),
            ("Cursor", "com.todesktop.230313mzl4w4u92"),
            ("Windsurf", "com.exafunction.windsurf"),
            ("Zed", "dev.zed.Zed"),
            ("Sublime Text", "com.sublimetext.4"),
        ]
        var found: [(String, URL)] = []
        for candidate in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) {
                found.append((candidate.name, url))
                continue
            }
            let direct = URL(fileURLWithPath: "/Applications/\(candidate.name).app")
            if FileManager.default.fileExists(atPath: direct.path) {
                found.append((candidate.name, direct))
            }
        }
        return found
    }

    /// 菜单上显示的编辑器名字。没有装任何编辑器时返回 nil。
    static var preferredEditorName: String? { detectedEditors().first?.name }

    /// 用已安装的代码编辑器打开。一个都没有就退回系统默认方式。
    static func openInCodeEditor(_ url: URL) {
        guard let editor = detectedEditors().first else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: editor.url, configuration: NSWorkspace.OpenConfiguration())
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

    /// 两个路径是否在同一个宗卷上。
    ///
    /// 这不是优化，是**安全保证的前提**：同宗卷的 `moveItem` 在内核层面就是一次
    /// 原子重命名 —— 要么完成，要么完全没发生，**不可能出现「源没了、目标也没有」
    /// 的中间态**。跨宗卷时 Foundation 内部会退化成「复制 + 删除」，那条路径
    /// 中途失败时的行为我没有验证过，也不打算拿用户的数据去验证，所以直接拒绝。
    private static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let va = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let vb = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let va, let vb else { return false }
        return String(describing: va) == String(describing: vb)
    }

    /// 搬移结果。`moved` 记录「从哪搬到哪」，调用方据此决定哪些条目真的成功了
    /// —— 只有成功的才允许从整理框里摘掉。
    struct MoveOutcome {
        var moved: [(from: URL, to: URL)] = []
        var failures: [(url: URL, reason: String)] = []
    }

    /// 独占重命名用的标志（Darwin 的 `RENAME_EXCL`）。
    private static let renameExclusive: UInt32 = 0x0000_0004

    /// 把文件移进某个文件夹。
    ///
    /// **搬移原语是 `renamex_np(RENAME_EXCL)`，不是 `FileManager.moveItem`。** 理由：
    /// - 它由内核保证：同设备 = 一次原子重命名，要么完成要么完全没发生，
    ///   不可能出现「源没了、目标也没有」。
    /// - 不同设备时内核返回 `EXDEV`，**永远不会**退化成「复制 + 删除」——
    ///   这正是之前丢文件的那条路。遇到 EXDEV 我们直接拒绝并提示用访达。
    /// - `RENAME_EXCL` 保证目标已存在时失败（`EEXIST`），**绝不覆盖同名文件**；
    ///   而 POSIX 的 `rename(2)` 是会覆盖的，这里不能直接用。
    ///
    /// 失败时源文件一定原封不动。
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
            if src.deletingLastPathComponent().path == destinationRoot.path { continue }
            if destinationRoot.path == src.path || destinationRoot.path.hasPrefix(src.path + "/") {
                outcome.failures.append((src, "不能把文件夹移进它自己")); continue
            }
            if BoxConfig.isProtected(src) {
                outcome.failures.append((src, "受保护的路径")); continue
            }

            OperationsLog.append("移入文件夹: \(src.path) -> \(destinationRoot.path)")

            // 目标同名时自动加序号。RENAME_EXCL 会挡住并发抢建，所以这里最多重试几次。
            var landed: URL?
            var lastError = ""
            for _ in 0..<64 {
                let destination = uniqueDestination(for: src, in: destinationRoot)
                let code = exclusiveRename(src, destination)
                if code == 0 {
                    landed = destination
                    break
                }
                if errno == EEXIST { continue }          // 刚被别的东西占了，换个名字再来
                lastError = String(cString: strerror(errno))
                break
            }

            if let landed {
                outcome.moved.append((from: src, to: landed))
                OperationsLog.append("  成功 -> \(landed.path)")
            } else {
                let reason = lastError.isEmpty ? "重命名失败" : lastError
                let friendly = reason.contains("Cross-device") || reason.contains("cross-device")
                    ? "目标在不同磁盘上，请用访达操作"
                    : reason
                outcome.failures.append((src, friendly))
                OperationsLog.append("  失败（源文件保持不动）: \(reason)")
            }
        }
        return outcome
    }

    /// 同名文件自动加序号，**绝不覆盖**。
    /// 注意 `RENAME_EXCL` 已经在内核层面兜住了并发抢建，这里只是给出候选名字。
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

    /// 独占重命名。返回 0 表示成功，非 0 时 `errno` 有效。
    private static func exclusiveRename(_ from: URL, _ to: URL) -> Int32 {
        from.withUnsafeFileSystemRepresentation { src in
            to.withUnsafeFileSystemRepresentation { dst in
                guard let src, let dst else { return Int32(EINVAL) }
                return renamex_np(src, dst, renameExclusive)
            }
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
