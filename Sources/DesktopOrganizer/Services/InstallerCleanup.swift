import AppKit

/// 装好之后自己收拾干净：把还挂着的安装盘弹出，把安装包丢进废纸篓。
///
/// 只在「程序已经位于 /Applications」时才会跑，而且**一辈子只跑一次** ——
/// 否则以后每次启动都会把新下载的安装包删掉。
enum InstallerCleanup {

    static func runIfNeeded() {
        let store = Store.shared
        guard store.prefs.removeInstallerAfterInstall, !store.prefs.didRunInstallerCleanup else { return }

        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        guard bundlePath.hasPrefix("/Applications/") else { return }

        // 等程序站稳了再动手，避免和启动流程抢
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            ejectOurVolumes { ejected in
                let trashed = trashInstallerImages()
                store.prefs.didRunInstallerCleanup = true
                if ejected > 0 || trashed > 0 {
                    NSLog("[桌面整理] 安装清理：弹出 %ld 个安装盘，移除 %ld 个安装包", ejected, trashed)
                }
            }
        }
    }

    // MARK: 弹出安装盘

    private static func ejectOurVolumes(completion: @escaping (Int) -> Void) {
        let appName = Bundle.main.bundleURL.lastPathComponent
        let runningParent = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path

        // 不跳过隐藏卷：用 -nobrowse 挂载的安装盘会被标成隐藏卷，
        // 而「卷里躺着我们的 app」这个条件已经足够精确地认出自己的安装盘。
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: []
        ) ?? []

        // 只处理「根目录里躺着我们这个 app」的卷，也就是我们自己的安装盘
        let targets = volumes.filter { volume in
            guard volume.path != "/" else { return false }
            guard volume.standardizedFileURL.path != runningParent else { return false }
            return FileManager.default.fileExists(atPath: volume.appendingPathComponent(appName).path)
        }

        guard !targets.isEmpty else {
            completion(0)
            return
        }

        var ejected = 0
        for volume in targets where eject(volume) {
            ejected += 1
        }
        completion(ejected)
    }

    /// 先走 NSWorkspace；它在某些情况下会静默失败，再退回 hdiutil。
    private static func eject(_ volume: URL) -> Bool {
        if (try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)) != nil {
            return true
        }
        if runDetach(volume, force: false) { return true }
        return runDetach(volume, force: true)
    }

    private static func runDetach(_ volume: URL, force: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = force ? ["detach", volume.path, "-force"] : ["detach", volume.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: 安装包丢废纸篓

    private static func trashInstallerImages() -> Int {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let searchDirs = ["Downloads", "Desktop"].map { home.appendingPathComponent($0) }

        // 程序自己的创建时间：比它新的安装包不动，避免误删刚下载的新版
        let appCreated = try? Bundle.main.bundleURL
            .resourceValues(forKeys: [.creationDateKey]).creationDate

        var removed = 0
        for dir in searchDirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.lowercased().hasSuffix(".dmg") && isOurs(name) {
                let url = dir.appendingPathComponent(name)
                if let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   let appCreated, created > appCreated {
                    continue
                }
                if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                    removed += 1
                }
            }
        }
        return removed
    }

    private static func isOurs(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return lower.contains("桌面整理") || lower.contains("desktoporganizer")
    }
}
