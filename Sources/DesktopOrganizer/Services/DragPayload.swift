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

    /// 这次拖拽**是否被允许落到应用之外**（也就是用户按住了 ⌥）。
    /// 只有这种情况系统才可能接手、并在桌面留下「剪贴文件」。
    /// 剪贴文件清理只在这种情况下才允许跑 —— 自动删除的触发面越小越好。
    @Published var outsideAllowed = false

    func begin(_ payload: DragPayload) {
        self.payload = payload
        handled = false
        folderDropTargetID = nil
        outsideAllowed = false
    }

    func finish() {
        payload = nil
        handled = false
        folderDropTargetID = nil
        outsideAllowed = false
    }
}
