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

/// 桌面分类。**只读取，不移动任何文件** —— 结果是一批装满了「引用」的整理框。
enum DeskCategorizer {

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
        if type.conforms(to: .spreadsheet) || type.conforms(to: .presentation)
            || type.conforms(to: .pdf) || type.conforms(to: .rtf) { return .document }
        if type.conforms(to: .text) { return .document }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .diskImage) { return .installer }
        if type.conforms(to: .application) { return .application }
        return .other
    }

    /// 扫描桌面顶层并按类型分组。会跳过：隐藏文件、程序自身所在目录、桌面根目录。
    static func scanDesktop() -> [FileCategory: [URL]] {
        let fm = FileManager.default
        let desktop = AppPaths.desktopDirectory.standardizedFileURL
        guard let names = try? fm.contentsOfDirectory(atPath: desktop.path) else { return [:] }

        var groups: [FileCategory: [URL]] = [:]
        for name in names {
            if name.hasPrefix(".") { continue }
            let url = desktop.appendingPathComponent(name).standardizedFileURL
            if BoxConfig.isProtected(url) { continue }
            guard fm.fileExists(atPath: url.path) else { continue }
            groups[category(for: url), default: []].append(url)
        }
        return groups
    }

    struct Outcome {
        var createdBoxes: Int = 0
        var addedItems: Int = 0
        var lines: [String] = []
        var summary: String = ""
    }

    /// 把桌面项目按类型收进对应的整理框。**文件一个都不动。**
    static func categorizeIntoBoxes() -> Outcome {
        let store = Store.shared
        let groups = scanDesktop()
        var outcome = Outcome()

        let ordered = FileCategory.allCases.filter { !(groups[$0]?.isEmpty ?? true) }
        guard !ordered.isEmpty else {
            outcome.summary = "桌面很干净，没有需要归类的东西。"
            return outcome
        }

        for category in ordered {
            guard let urls = groups[category], !urls.isEmpty else { continue }

            let boxID: UUID
            if let existing = store.boxes.first(where: { $0.name == category.rawValue }) {
                boxID = existing.id
            } else {
                let box = store.addBox(name: category.rawValue)
                store.update(id: box.id) { $0.accentHex = category.accentHex }
                boxID = box.id
                outcome.createdBoxes += 1
            }

            let added = store.addItems(urls, to: boxID)
            outcome.addedItems += added
            outcome.lines.append("\(category.rawValue)：\(added) 项")
        }

        var summary = "已把 \(outcome.addedItems) 项收进整理框\n\n"
        summary += outcome.lines.joined(separator: "\n")
        summary += "\n\n文件没有被移动，只是被整理框引用了。"
        outcome.summary = summary
        return outcome
    }
}
