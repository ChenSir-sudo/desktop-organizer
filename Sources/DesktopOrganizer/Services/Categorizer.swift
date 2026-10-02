import AppKit
import UniformTypeIdentifiers

enum FileCategory: String, CaseIterable {
    case image = "图片"
    case document = "文档"
    case video = "视频"
    case audio = "音频"
    case archive = "压缩包"
    case installer = "安装包"
    case application = "应用"
    case code = "代码"
    case folder = "文件夹"
    case other = "其他"

    var accentHex: String {
        switch self {
        case .image: return "FF375F"
        case .document: return "0A84FF"
        case .video: return "BF5AF2"
        case .audio: return "FF9F0A"
        case .archive: return "8E8E93"
        case .installer: return "64D2FF"
        case .application: return "30D158"
        case .code: return "5AC8FA"
        case .folder: return "FFD60A"
        case .other: return "98989D"
        }
    }
}

enum DeskSorter {
    struct GroupResult {
        var category: FileCategory
        var folder: URL
        var result: FileMover.Result
    }

    // 按扩展名先做一次显式判断，比 UTType 更可预测
    private static let installExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "zst", "lz4", "cab", "jar"
    ]
    private static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "jsx", "tsx", "json", "yml", "yaml", "sh", "zsh", "bash",
        "html", "css", "scss", "xml", "toml", "rb", "go", "rs", "java", "kt", "c", "cpp", "h",
        "hpp", "m", "mm", "sql", "pl", "lua", "vue", "svelte", "ipynb", "gradle", "cmake"
    ]

    static func category(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            return ext == "app" ? .application : .folder
        }
        if ext.isEmpty { return .other }
        if installExtensions.contains(ext) { return .installer }
        if archiveExtensions.contains(ext) { return .archive }
        if codeExtensions.contains(ext) { return .code }

        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .code }
        if type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) || type.conforms(to: .pdf) || type.conforms(to: .rtf) {
            return .document
        }
        if type.conforms(to: .text) { return .document }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .diskImage) { return .installer }
        if type.conforms(to: .application) { return .application }
        return .other
    }

    /// 扫描桌面顶层，按类型分组。会跳过：隐藏文件、整理根目录、各整理框的目标文件夹、程序自身所在目录。
    static func scanDesktop() -> [FileCategory: [URL]] {
        let fm = FileManager.default
        let desktop = AppPaths.desktopDirectory.standardizedFileURL
        let excluded = excludedPaths()

        guard let names = try? fm.contentsOfDirectory(atPath: desktop.path) else { return [:] }

        var groups: [FileCategory: [URL]] = [:]
        for name in names {
            if name.hasPrefix(".") { continue }
            let url = desktop.appendingPathComponent(name).standardizedFileURL
            if excluded.contains(url.path) { continue }
            if FileMover.isInsideRunningApp(url) { continue }
            // 跳过符号链接之外的普通项即可，不存在的项忽略
            guard fm.fileExists(atPath: url.path) else { continue }
            groups[category(for: url), default: []].append(url)
        }
        return groups
    }

    private static func excludedPaths() -> Set<String> {
        var set = Set<String>()
        let desktopPath = AppPaths.desktopDirectory.standardizedFileURL.path
        let store = Store.shared

        set.insert(store.prefs.rootURL.standardizedFileURL.path)
        for box in store.boxes {
            set.insert(box.folderURL.standardizedFileURL.path)
        }
        // 保护：程序自己所在的顶层目录（例如从某个项目目录里运行）
        var cursor = Bundle.main.bundleURL.standardizedFileURL
        while cursor.path != "/" && cursor.path != desktopPath {
            if cursor.deletingLastPathComponent().path == desktopPath {
                set.insert(cursor.path)
                break
            }
            cursor = cursor.deletingLastPathComponent()
        }
        return set
    }

    /// 真正执行分类：为每个有内容的分类准备文件夹和整理框，然后移动文件。
    static func organize() -> (results: [GroupResult], summary: String) {
        let store = Store.shared
        let groups = scanDesktop()

        var results: [GroupResult] = []
        var lines: [String] = []

        let ordered = FileCategory.allCases.filter { groups[$0]?.isEmpty == false }

        for category in ordered {
            guard let urls = groups[category], !urls.isEmpty else { continue }
            let folder = store.prefs.rootURL.appendingPathComponent(category.rawValue, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            if store.box(withFolder: folder.standardizedFileURL.path) == nil
                && store.box(withFolder: folder.path) == nil {
                store.addBox(name: category.rawValue, folder: folder)
            }

            let result = FileMover.move(urls, into: folder)
            results.append(GroupResult(category: category, folder: folder, result: result))

            var line = "\(category.rawValue)：\(result.moved.count) 项"
            if !result.failures.isEmpty {
                line += "（\(result.failures.count) 项失败）"
            }
            lines.append(line)
        }

        if results.isEmpty {
            return ([], "桌面很干净，没有需要整理的文件。")
        }

        let totalMoved = results.reduce(0) { $0 + $1.result.moved.count }
        var summary = "共整理 \(totalMoved) 项文件\n\n" + lines.joined(separator: "\n")
        summary += "\n\n归档位置：\(store.prefs.rootURL.path)"
        return (results, summary)
    }
}
