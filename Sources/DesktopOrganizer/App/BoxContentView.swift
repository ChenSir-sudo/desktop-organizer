import AppKit

/// 整理框窗口的内容视图，负责接收**外部文件拖入**。
///
/// 为什么不用 SwiftUI 的 `.onDrop`：那条链路要在 LazyVGrid / ScrollView / 卡片
/// 三层之间正确路由，实测「拖到格子之间会进、拖到空白处不进」，行为不稳定。
/// 直接把落点做在窗口内容视图上（AppKit 的 NSDraggingDestination），
/// 只要鼠标在窗口里就一定能收到。
///
/// 整理框内部的拖动（重排、跨框转移）仍然走 SwiftUI 的自定义拖拽类型，两边不冲突：
/// 这里只注册 `public.file-url`，外部文件走 AppKit，内部拖动走 SwiftUI。
final class BoxContentView: NSView {

    /// 外部文件落到窗口里。参数是文件列表和落点（本视图坐标系）。
    var onFileDrop: (([URL], NSPoint) -> Void)?
    /// 整理框内部的条目落到窗口里。参数是载荷和目标位置。
    var onItemDrop: ((DragPayload, Int) -> Void)?
    /// 拖拽进入/离开，用来驱动高亮。
    var onTargetingChanged: ((Bool) -> Void)?

    /// 各条目格子在本视图坐标系里的位置（由 SwiftUI 侧上报），
    /// 用来判断内部条目落到了第几个位置。
    var tileFrames: [UUID: CGRect] = [:]
    /// 当前显示顺序，用来把落点换算成插入下标。
    var orderedItemIDs: [UUID] = []

    private static let logURL: URL = AppPaths.supportDirectory.appendingPathComponent("drop.log")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, DragPayload.pasteboardType])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    // MARK: NSDraggingDestination

    private func acceptedOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(sender) { return .copy }
        if DragPayload.read(from: sender.draggingPasteboard) != nil { return .move }
        return []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = acceptedOperation(sender)
        log("draggingEntered types=\(sender.draggingPasteboard.types?.map(\.rawValue) ?? []) -> \(op == [] ? "拒绝" : "接受")")
        if op != [] { onTargetingChanged?(true) }
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedOperation(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetingChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptedOperation(sender) != []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetingChanged?(false)
        let point = convert(sender.draggingLocation, from: nil)
        let pasteboard = sender.draggingPasteboard

        // 内部条目：重排 / 跨框转移
        if let payload = DragPayload.read(from: pasteboard) {
            let index = insertionIndex(at: point)
            log("performDragOperation 内部条目 落点=\(NSStringFromPoint(point)) 目标下标=\(index)")
            onItemDrop?(payload, index)
            return true
        }

        // 外部文件
        let urls = fileURLs(from: pasteboard)
        log("performDragOperation 外部文件 落点=\(NSStringFromPoint(point)) 数量=\(urls.count) -> \(urls.map(\.lastPathComponent))")
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls, point)
        return true
    }

    /// 把窗口坐标的落点换算成插入下标。SwiftUI 的 .global 是左上原点，本视图是左下原点。
    private func insertionIndex(at point: NSPoint) -> Int {
        let flipped = NSPoint(x: point.x, y: bounds.height - point.y)
        for (index, id) in orderedItemIDs.enumerated() {
            if let frame = tileFrames[id], frame.contains(flipped) {
                return index
            }
        }
        return orderedItemIDs.count
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onTargetingChanged?(false)
    }

    // MARK: 取文件

    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        hasFileURLs(sender.draggingPasteboard)
    }

    private func hasFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL]) ?? []
    }

    // MARK: 日志

    /// 拖拽出问题时靠它定位：记录窗口究竟收到了什么。文件很小，保留最近 200 行。
    private func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        let url = Self.logURL

        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        existing += line
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 200 {
            existing = lines.suffix(200).joined(separator: "\n")
        }
        try? existing.write(to: url, atomically: true, encoding: .utf8)
    }
}
