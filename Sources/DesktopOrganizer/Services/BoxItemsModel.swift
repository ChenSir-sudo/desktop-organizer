import AppKit
import Combine
import UniformTypeIdentifiers

/// 解析后的条目：把「路径引用」变成能直接渲染的东西。
struct ResolvedItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let exists: Bool
    let isDirectory: Bool
    let isApplication: Bool

    var icon: NSImage {
        IconCache.icon(for: url, isDirectory: isDirectory, isApplication: isApplication)
    }

    var isBroken: Bool { !exists }

    static func == (lhs: ResolvedItem, rhs: ResolvedItem) -> Bool {
        lhs.id == rhs.id && lhs.exists == rhs.exists
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(exists)
    }
}

/// 图标缓存：按扩展名缓存，避免每次重绘都问一遍 LaunchServices。
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL, isDirectory: Bool, isApplication: Bool) -> NSImage {
        if isApplication { return systemIcon(.application) }
        if isDirectory { return systemIcon(.folder) }
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
        image.size = NSSize(width: 64, height: 64)
        return image
    }
}

/// 一个整理框的内容模型。条目都是**引用**，文件留在原地。
final class BoxItemsModel: ObservableObject {
    @Published private(set) var items: [ResolvedItem] = []
    @Published private(set) var missingCount: Int = 0

    private let boxID: UUID
    private var timer: Timer?
    private var lastSignature = ""

    init(boxID: UUID) {
        self.boxID = boxID
        refresh(force: true)
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh(force: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    /// 重新解析所有引用。文件的增删改由外部发生，所以定期检查一次存在性，
    /// 但用签名比对避免无意义的视图刷新。
    func refresh(force: Bool) {
        guard let box = Store.shared.box(id: boxID) else {
            if !items.isEmpty { items = []; missingCount = 0 }
            return
        }

        var resolved: [ResolvedItem] = []
        resolved.reserveCapacity(box.items.count)

        for item in box.items {
            let info = item.url.fileInfo
            resolved.append(
                ResolvedItem(
                    id: item.id,
                    url: item.url,
                    name: item.name,
                    exists: info.exists,
                    isDirectory: info.isDirectory,
                    isApplication: item.url.pathExtension.lowercased() == "app"
                )
            )
        }

        let signature = resolved.map { "\($0.id.uuidString)\($0.exists ? "1" : "0")" }.joined(separator: "|")
        guard force || signature != lastSignature else { return }
        lastSignature = signature
        items = resolved
        missingCount = box.missingItemCount
    }

}
