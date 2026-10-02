import AppKit

/// 整理框内部拖拽时携带的数据：**一次可以拖多个条目**。
///
/// 刻意不把载荷声明成导出的 UTI，也不让外部进程可见 —— 否则往访达拖的时候
/// 系统会把它当文件内容写出来，在桌面生成垃圾文件。
struct DragPayload: Equatable {
    var boxID: UUID
    var itemIDs: [UUID]

    static let typeIdentifier = "com.chenziyang.desktoporganizer.item"

    init(boxID: UUID, itemIDs: [UUID]) {
        self.boxID = boxID
        self.itemIDs = itemIDs
    }

    init?(string: String) {
        let parts = string.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let boxID = UUID(uuidString: String(parts[0])) else { return nil }
        let ids = parts[1].split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        guard !ids.isEmpty else { return nil }
        self.boxID = boxID
        self.itemIDs = ids
    }

    var encoded: String {
        "\(boxID.uuidString)|\(itemIDs.map(\.uuidString).joined(separator: ","))"
    }

    // MARK: 粘贴板（AppKit 层用）

    static var pasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(typeIdentifier)
    }

    static func read(from pasteboard: NSPasteboard) -> DragPayload? {
        guard let data = pasteboard.data(forType: pasteboardType),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return DragPayload(string: string)
    }

    // MARK: 拖拽源（SwiftUI 层用）

    /// 拖拽源。
    ///
    /// 可见性必须是 .all：设成 .ownProcess 时数据**根本不写到粘贴板上**，
    /// 连本进程的落点都读不到（日志里表现为 draggingEntered 直接「拒绝」，
    /// 框内拖拽全部失效）。
    ///
    /// 同时把文件的 URL 也放进去 —— 这样拖到整理框**外面**的目录时，
    /// 访达会把文件真的移进去，不需要我们自己去找目标目录。
    static func provider(for payload: DragPayload, fileURLs: [URL]) -> NSItemProvider {
        let provider = NSItemProvider()

        let data = Data(payload.encoded.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }

        // 单个文件：标准的 public.file-url
        if let first = fileURLs.first {
            provider.registerDataRepresentation(
                forTypeIdentifier: "public.file-url",
                visibility: .all
            ) { completion in
                completion(first.dataRepresentation, nil)
                return nil
            }
        }

        // 多个文件：访达仍然认的旧式文件名列表（属性列表数组）
        let paths = fileURLs.map(\.path)
        if paths.count > 1,
           let plist = try? PropertyListSerialization.data(
               fromPropertyList: paths, format: .binary, options: 0) {
            provider.registerDataRepresentation(
                forTypeIdentifier: "NSFilenamesPboardType",
                visibility: .all
            ) { completion in
                completion(plist, nil)
                return nil
            }
        }

        return provider
    }
}

/// 一个条目格子在本窗口里的位置与身份。
/// SwiftUI 侧上报给 AppKit 侧，用来把落点换算成「第几个格子」以及
/// 「是不是文件夹」—— 拖到文件夹图标上要真的能放进去。
struct TileGeometry: Equatable {
    var id: UUID
    var frame: CGRect      // SwiftUI 的 .global：窗口坐标，左上原点
    var isDirectory: Bool
    var url: URL
}

/// 全局拖拽状态。必须共享，因为「从 A 框拖到 B 框」时，
/// B 框的视图看不到 A 框自己的 UI 状态。
final class DragSession: ObservableObject {
    static let shared = DragSession()

    /// 当前正在被拖动的条目
    @Published var payload: DragPayload?
    /// 是否已经被某个整理框接住了（用来区分「拖到别的框」和「拖出去丢掉」）
    @Published var handled = false
    /// 正悬停在哪个文件夹图标上（内部条目和外部文件都用它做高亮提示）
    @Published var folderDropTargetID: UUID?

    func begin(_ payload: DragPayload) {
        self.payload = payload
        handled = false
        folderDropTargetID = nil
    }

    func finish() {
        payload = nil
        handled = false
        folderDropTargetID = nil
    }
}
