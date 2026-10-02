import AppKit

/// 整理框窗口的内容视图。它同时是**拖拽落点**和**拖拽源**。
///
/// 为什么两块都放在 AppKit 而不是 SwiftUI：
/// - 落点：SwiftUI 只要检测到任何 `.onDrop` 就会注册一个 `public.data` 落点，
///   而 `public.file-url` 符合 `public.data`，文件拖拽会被它抢走、到不了这里。
/// - 拖拽源：SwiftUI 的 `.onDrag` 只能给**一个** NSItemProvider，也就只能带一个
///   文件 URL。多选拖到访达的目录里时只有第一个文件会被搬走。用
///   `NSDraggingSession` 才能一个文件一个粘贴板项，整批搬走。
final class BoxContentView: NSView, NSDraggingSource {

    // MARK: 落点回调

    /// 外部文件落到窗口里。第三个参数是落点所在的文件夹图标（不是文件夹则为 nil）。
    var onFileDrop: (([URL], NSPoint, URL?) -> Void)?
    /// 整理框内部的条目落到窗口里。参数是载荷、目标位置、以及落点所在的文件夹。
    var onItemDrop: ((DragPayload, Int, URL?) -> Void)?
    /// 拖拽进入/离开，用来驱动高亮。
    var onTargetingChanged: ((Bool) -> Void)?
    /// 当前悬停在哪个文件夹图标上（nil 表示没有）。
    var onFolderTargetChanged: ((UUID?) -> Void)?

    // MARK: 拖拽源回调

    /// 单击选中某个条目，附带修饰键（⌘ / ⇧）。
    var onSelectionChange: ((UUID, NSEvent.ModifierFlags) -> Void)?
    /// 双击打开某个条目。
    var onOpenItem: ((UUID) -> Void)?
    /// 即将开始拖动这些条目 —— 控制器趁机先把文件恢复显示。
    var onDragWillBegin: (([UUID]) -> Void)?
    /// 当前选中的条目（由控制器提供）。
    var selectionProvider: (() -> Set<UUID>)?
    /// 本框的 ID。
    var boxID: UUID?

    // MARK: 几何

    /// 各条目格子的几何（由 SwiftUI 侧上报）。
    var tiles: [UUID: TileGeometry] = [:]
    /// 当前显示顺序。
    var orderedItemIDs: [UUID] = []

    private var pressPoint: NSPoint?
    private var pressedTileID: UUID?
    private var didStartDrag = false

    private static let logURL: URL = AppPaths.supportDirectory.appendingPathComponent("drop.log")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, DragPayload.pasteboardType])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现")
    }

    // MARK: - 命中测试

    /// 只在**左键按在条目格子上**时接管事件；其余（悬浮、右键菜单、滚轮）
    /// 一律放行给下面的 SwiftUI 宿主视图，保持原有交互。
    override func hitTest(_ point: NSPoint) -> NSView? {
        if didStartDrag { return self }
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            return tile(at: point) != nil ? self : nil
        default:
            return nil
        }
    }

    // MARK: - 拖拽源

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = tile(at: point) else { return }

        if event.clickCount == 2 {
            onOpenItem?(hit.id)
            return
        }
        pressPoint = point
        pressedTileID = hit.id
        didStartDrag = false
        onSelectionChange?(hit.id, event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let start = pressPoint, let anchor = pressedTileID else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        didStartDrag = true
        beginDrag(with: event, anchor: anchor)
    }

    override func mouseUp(with event: NSEvent) {
        pressPoint = nil
        pressedTileID = nil
        didStartDrag = false
    }

    /// 一个文件一个 NSDraggingItem —— 这样访达才能整批搬走多选的文件。
    private func beginDrag(with event: NSEvent, anchor: UUID) {
        let selected = selectionProvider?() ?? []
        var ids = selected.contains(anchor) ? orderedItemIDs.filter { selected.contains($0) } : [anchor]
        if ids.isEmpty { ids = [anchor] }

        onDragWillBegin?(ids)

        guard let boxID else { return }
        let payload = DragPayload(boxID: boxID, itemIDs: ids)
        DragSession.shared.begin(payload)

        var draggingItems: [NSDraggingItem] = []
        for id in ids {
            guard let tile = tiles[id] else { continue }
            let boardItem = NSPasteboardItem()
            boardItem.setData(tile.url.dataRepresentation, forType: .fileURL)
            boardItem.setData(Data(payload.encoded.utf8), forType: DragPayload.pasteboardType)

            let draggingItem = NSDraggingItem(pasteboardWriter: boardItem)
            draggingItem.setDraggingFrame(
                viewRect(fromSwiftUI: tile.frame),
                contents: NSWorkspace.shared.icon(forFile: tile.url.path)
            )
            draggingItems.append(draggingItem)
        }
        guard !draggingItems.isEmpty else { return }

        log("开始拖动 \(ids.count) 个条目（一个文件一个粘贴板项）")
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    /// 应用内：移动（重排 / 跨框转移）。应用外：也允许移动，访达才能把文件搬进目标目录。
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : [.move, .copy]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    // MARK: - 落点

    /// 是不是整理框自己发起的拖拽。只看**类型在不在**，不看数据能不能读到 ——
    /// 数据是懒加载的，拖拽刚进入时还不一定读得到。
    private func isInternalDrag(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.types?.contains(DragPayload.pasteboardType) ?? false
    }

    private func acceptedOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isInternalDrag(sender) { return .move }
        if hasFileURLs(sender.draggingPasteboard) { return .copy }
        return []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = acceptedOperation(sender)
        log("draggingEntered types=\(sender.draggingPasteboard.types?.map(\.rawValue) ?? []) -> \(op == [] ? "拒绝" : "接受")")
        if op != [] { onTargetingChanged?(true) }
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = acceptedOperation(sender)
        let point = convert(sender.draggingLocation, from: nil)
        onFolderTargetChanged?(folderTile(at: point)?.id)
        return op
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetingChanged?(false)
        onFolderTargetChanged?(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptedOperation(sender) != []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetingChanged?(false)
        onFolderTargetChanged?(nil)
        let point = convert(sender.draggingLocation, from: nil)
        let pasteboard = sender.draggingPasteboard
        let folder = folderTile(at: point)?.url

        if isInternalDrag(sender), let payload = DragPayload.read(from: pasteboard) {
            let index = insertionIndex(at: point)
            log("performDragOperation 内部条目 \(payload.itemIDs.count) 项 落点=\(NSStringFromPoint(point)) 下标=\(index) 目标文件夹=\(folder?.lastPathComponent ?? "无")")
            onItemDrop?(payload, index, folder)
            return true
        }

        let urls = fileURLs(from: pasteboard)
        log("performDragOperation 外部文件 \(urls.count) 个 落点=\(NSStringFromPoint(point)) 目标文件夹=\(folder?.lastPathComponent ?? "无") -> \(urls.map(\.lastPathComponent))")
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls, point, folder)
        return true
    }

    // MARK: 几何换算

    /// SwiftUI 的 .global 是窗口坐标、左上原点；本视图是左下原点。
    private func flipped(_ point: NSPoint) -> NSPoint {
        NSPoint(x: point.x, y: bounds.height - point.y)
    }

    private func viewRect(fromSwiftUI frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: bounds.height - frame.maxY,
               width: frame.width, height: frame.height)
    }

    private func tile(at point: NSPoint) -> TileGeometry? {
        let target = flipped(point)
        for id in orderedItemIDs {
            if let tile = tiles[id], tile.frame.contains(target) { return tile }
        }
        return nil
    }

    private func folderTile(at point: NSPoint) -> TileGeometry? {
        guard let tile = tile(at: point), tile.isDirectory else { return nil }
        return tile
    }

    private func insertionIndex(at point: NSPoint) -> Int {
        guard let hit = tile(at: point) else { return orderedItemIDs.count }
        return orderedItemIDs.firstIndex(of: hit.id) ?? orderedItemIDs.count
    }

    // MARK: 取文件

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

    /// 供外部记一笔（例如几何上报），便于排查。
    func note(_ message: String) { log(message) }

    /// 拖拽出问题时靠它定位：记录窗口究竟收到了什么。文件很小，保留最近 200 行。
    private func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var existing = (try? String(contentsOf: Self.logURL, encoding: .utf8)) ?? ""
        existing += "[\(stamp)] \(message)\n"
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > 200 {
            existing = lines.suffix(200).joined(separator: "\n")
        }
        try? existing.write(to: Self.logURL, atomically: true, encoding: .utf8)
    }
}
