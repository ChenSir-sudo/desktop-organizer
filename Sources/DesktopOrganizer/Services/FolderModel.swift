import AppKit
import Combine
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isApplication: Bool
    let sizeText: String?

    var id: URL { url }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }

    var icon: NSImage {
        IconCache.icon(for: url, isDirectory: isDirectory, isApplication: isApplication)
    }
}

enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL, isDirectory: Bool, isApplication: Bool) -> NSImage {
        if isDirectory && !isApplication {
            return systemIcon(.folder)
        }
        if isApplication {
            return systemIcon(.application)
        }
        let ext = url.pathExtension.lowercased()
        let key = ext.isEmpty ? "__file__" : ext
        if let cached = cache[key] { return cached }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        let image = systemIcon(type)
        cache[key] = image
        return image
    }

    private static func systemIcon(_ type: UTType) -> NSImage {
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 48, height: 48)
        return image
    }
}

/// 监听一个文件夹的内容，用于整理框里显示文件网格。
final class FolderModel: ObservableObject {
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var errorText: String?

    let folder: URL
    private var timer: Timer?
    private var lastModification: Date?

    private let displayLimit = 150

    init(folder: URL) {
        self.folder = folder
        refresh(force: true)
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    func refresh(force: Bool) {
        let fm = FileManager.default
        let attributes = try? fm.attributesOfItem(atPath: folder.path)
        let modification = attributes?[.modificationDate] as? Date

        if !force, let modification, modification == lastModification {
            return
        }
        lastModification = modification

        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else {
            items = []
            totalCount = 0
            errorText = "无法读取文件夹（可能需要在「系统设置 › 隐私与安全性 › 文件与文件夹」中授权）"
            return
        }
        errorText = nil

        var collected: [FileItem] = []
        collected.reserveCapacity(names.count)

        for name in names {
            if name.hasPrefix(".") { continue }
            let url = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            let isApp = url.pathExtension.lowercased() == "app"
            collected.append(
                FileItem(
                    url: url,
                    name: name,
                    isDirectory: isDirectory.boolValue,
                    isApplication: isApp,
                    sizeText: nil
                )
            )
        }

        collected.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        totalCount = collected.count
        items = Array(collected.prefix(displayLimit))
    }
}
