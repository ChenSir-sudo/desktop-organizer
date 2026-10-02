import Foundation

/// 文件隐藏标志（BSD 的 UF_HIDDEN）。
///
/// 语义：文件**留在完全相同的路径**，git / IDE / 构建缓存一概不受影响，
/// 但访达和桌面不再显示它。这跟「搬到别的文件夹」有本质区别。
///
/// 注意：`URL.resourceValues` 会在 URL 实例上缓存结果。设完标志后必须
/// `removeAllCachedResourceValues()` 再读，否则拿到的是旧值 —— 曾经因为这个
/// 让 didHide 永远是 false，结果「从框中移除」后文件再也恢复不出来。
enum HiddenFlag {

    static func isHidden(_ url: URL) -> Bool {
        var probe = url
        probe.removeAllCachedResourceValues()
        if let value = try? probe.resourceValues(forKeys: [.isHiddenKey]).isHidden {
            return value
        }
        return chflagsIsHidden(url)
    }

    @discardableResult
    static func setHidden(_ hidden: Bool, for url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        if isHidden(url) == hidden { return true }

        var mutable = url
        mutable.removeAllCachedResourceValues()
        var values = URLResourceValues()
        values.isHidden = hidden
        _ = try? mutable.setResourceValues(values)

        if isHidden(url) == hidden { return true }

        // URLResourceValues 在某些卷上不可写，退回到 chflags
        runChflags(hidden, url)
        return isHidden(url) == hidden
    }

    // MARK: 兜底实现

    private static func chflagsIsHidden(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
        process.arguments = ["-f", "%Sf", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("hidden")
    }

    private static func runChflags(_ hidden: Bool, _ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        // -h：只改这个路径本身。不加的话符号链接会被"跟随"，
        // 结果改到链接指向的目标文件上，而不是链接本身。
        process.arguments = ["-h", hidden ? "hidden" : "nohidden", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
