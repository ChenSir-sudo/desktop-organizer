import Foundation

/// 真实的文件搬移逻辑：把拖进整理框的文件移动到框对应的文件夹。
enum FileMover {
    struct Result {
        var moved: [URL] = []
        var skipped: [URL] = []
        var failures: [(url: URL, reason: String)] = []

        var summary: String {
            var parts: [String] = []
            if !moved.isEmpty { parts.append("已整理 \(moved.count) 项") }
            if !skipped.isEmpty { parts.append("\(skipped.count) 项本来就在框内") }
            if !failures.isEmpty { parts.append("\(failures.count) 项失败") }
            return parts.isEmpty ? "没有变化" : parts.joined(separator: "，")
        }
    }

    static func move(_ urls: [URL], into folder: URL) -> Result {
        let fm = FileManager.default
        var result = Result()

        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destinationRoot = folder.standardizedFileURL

        for url in urls {
            let source = url.standardizedFileURL
            guard fm.fileExists(atPath: source.path) else {
                result.failures.append((source, "文件不存在"))
                continue
            }

            // 已经在目标文件夹里，跳过
            if source.deletingLastPathComponent().path == destinationRoot.path {
                result.skipped.append(source)
                continue
            }

            // 不允许把某个文件夹搬进它自己的子目录
            if destinationRoot.path.hasPrefix(source.path + "/") {
                result.failures.append((source, "不能把文件夹移动到它自己里面"))
                continue
            }

            // 不允许搬走正在运行的 app 自身
            if isInsideRunningApp(source) {
                result.failures.append((source, "这是程序自身所在位置，已跳过"))
                continue
            }

            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: source.path, isDirectory: &isDirectory)
            let destination = uniqueDestination(
                for: source.lastPathComponent,
                isDirectory: isDirectory.boolValue,
                in: destinationRoot
            )

            do {
                try fm.moveItem(at: source, to: destination)
                result.moved.append(destination)
            } catch {
                // 跨宗卷等情况下退化为复制 + 删除
                do {
                    try fm.copyItem(at: source, to: destination)
                    try fm.removeItem(at: source)
                    result.moved.append(destination)
                } catch let fallbackError {
                    result.failures.append((source, fallbackError.localizedDescription))
                }
            }
        }
        return result
    }

    /// 同名文件自动加序号：`报告.pdf` -> `报告 2.pdf`
    static func uniqueDestination(for name: String, isDirectory: Bool, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let base: String
        let ext: String
        if isDirectory {
            base = name
            ext = ""
        } else {
            base = (name as NSString).deletingPathExtension
            ext = (name as NSString).pathExtension
        }

        var counter = 2
        while counter < 9999 {
            let nextName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(nextName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
        return folder.appendingPathComponent("\(base) \(UUID().uuidString).\(ext)")
    }

    /// 判断某个路径是否是本程序 bundle 的一部分（避免把程序自己搬走）。
    static func isInsideRunningApp(_ url: URL) -> Bool {
        let appPath = Bundle.main.bundleURL.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        return target == appPath || appPath.hasPrefix(target + "/")
    }
}
