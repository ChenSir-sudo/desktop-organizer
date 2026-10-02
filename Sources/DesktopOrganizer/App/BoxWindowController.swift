import AppKit
import Combine
import SwiftUI

final class BoxWindowController: NSObject, NSWindowDelegate {

    static let minSize = CGSize(width: 230, height: 210)

    /// 不置顶时用的层级。
    ///
    /// 一开始这里用的是 `kCGDesktopIconWindowLevel`（桌面图标层），想让框永远待在
    /// 所有应用窗口下面。结果是**那个层级属于桌面本身**：一旦框不是创建时的最前状态，
    /// 鼠标点击和文件拖拽都不会投递给它 —— 看得见却完全够不着。
    /// 所以回到普通窗口层：不强行压在最上面，但和其它窗口一样可点、可拖、可接收拖入。
    static let normalLevel: NSWindow.Level = .normal

    private let store = Store.shared
    private(set) var boxID: UUID
    let panel: BoxPanel
    private(set) var itemsModel: BoxItemsModel
    let ui = BoxUIState()

    private var hostView: NSHostingView<AnyView>
    private let dropContainer = BoxContentView(frame: .zero)
    private var box: BoxConfig
    private var cancellables = Set<AnyCancellable>()

    // 拖动 / 缩放过程中的临时状态
    private var dragStartFrame: CGRect?
    private var dragMouseOffset: CGPoint?
    private var resizeStartFrame: CGRect?
    private var resizeStartMouse: CGPoint?
    private var isAdjustingFrame = false
    private var persistWorkItem: DispatchWorkItem?
    private var summonWorkItem: DispatchWorkItem?

    init(box: BoxConfig) {
        self.box = box
        self.boxID = box.id
        self.itemsModel = BoxItemsModel(boxID: box.id)
        self.panel = BoxPanel(
            contentRect: box.frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.hostView = NSHostingView(rootView: AnyView(EmptyView()))
        super.init()
        configurePanel()
        buildContent()
        panel.delegate = self
    }

    // MARK: 初始化

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // 阴影交给 SwiftUI
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = Self.minSize
        panel.level = box.floatOnTop ? .floating : Self.normalLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.setFrame(LayoutEngine.sanitize(box.frame, minSize: Self.minSize), display: false)

        // 内容视图是负责接收外部拖拽的 AppKit 视图；SwiftUI 宿主视图铺在它上面。
        // SwiftUI 那边不再注册 file-url（只保留内部拖拽用的自定义类型），
        // 所以外部文件一定会落到这层。
        // 层级：容器 > BoxContentView（在上，负责拖拽源/落点、条目点选） > SwiftUI 宿主视图
        // BoxContentView 的 hitTest 只在「左键按在条目格子上」时接管，
        // 其余事件放行给下面的宿主视图，所以悬浮、右键菜单等交互不受影响。
        let container = NSView(frame: CGRect(origin: .zero, size: panel.frame.size))
        container.autoresizingMask = [.width, .height]

        hostView.autoresizingMask = [.width, .height]
        hostView.frame = container.bounds
        container.addSubview(hostView)

        dropContainer.autoresizingMask = [.width, .height]
        dropContainer.frame = container.bounds
        container.addSubview(dropContainer)

        panel.contentView = container

        // 外部文件：落在文件夹图标上就移进那个文件夹，否则加入整理框
        dropContainer.onFileDrop = { [weak self] urls, _, folder in
            guard let self else { return }
            if let folder {
                let outcome = FileActions.move(urls, into: folder)
                BoxWindowManager.shared.refreshAll()
                if !outcome.failures.isEmpty {
                    FileActions.info(
                        title: "有 \(outcome.failures.count) 项没能移入「\(folder.lastPathComponent)」",
                        message: outcome.failures.map { "\($0.url.lastPathComponent)：\($0.reason)" }.joined(separator: "\n")
                    )
                }
            } else {
                self.handleDrop(urls)
            }
        }

        // 内部条目：放进文件夹 / 重排 / 跨框转移
        dropContainer.onItemDrop = { [weak self] payload, index, folder in
            guard let self else { return }
            DragSession.shared.handled = true
            defer { DragSession.shared.finish() }

            if let folder {
                Commands.moveItemsIntoFolder(payload.itemIDs, in: payload.boxID, folder: folder)
            } else if payload.boxID == self.boxID {
                Commands.reorder(in: self.boxID, itemIDs: payload.itemIDs, to: index)
            } else {
                Commands.transfer(itemIDs: payload.itemIDs, from: payload.boxID, to: self.boxID, at: index)
            }
        }

        dropContainer.onTargetingChanged = { [weak self] targeting in
            self?.ui.isDropTargeted = targeting
        }
        dropContainer.onFolderTargetChanged = { id in
            DragSession.shared.folderDropTargetID = id
        }
        dropContainer.boxID = boxID
        dropContainer.eventForwarder = hostView
        dropContainer.selectionProvider = { [weak self] in self?.ui.selectedItemIDs ?? [] }
        dropContainer.onSelectionChange = { [weak self] id, flags in
            self?.applySelection(to: id, flags: flags)
        }
        dropContainer.onClearSelection = { [weak self] in
            self?.ui.selectedItemIDs.removeAll()
        }
        dropContainer.onOpenItem = { id in
            guard let item = Store.shared.box(id: self.boxID)?.items.first(where: { $0.id == id }),
                  FileManager.default.fileExists(atPath: item.path) else { return }
            FileActions.open(item.url)
        }
        dropContainer.onDragWillBegin = { ids in
            // 先恢复显示：拖到框外是访达在搬文件，隐藏标志会跟着文件走
            Commands.unhideForDragging(ids, in: self.boxID)
        }
    }

    private func buildContent() {
        hostView.rootView = AnyView(
            BoxView(model: itemsModel, ui: ui, boxID: boxID, actions: makeActions())
                .environmentObject(store)
        )
    }

    private func makeActions() -> BoxActions {
        BoxActions(
            dragByMouse: { [weak self] in self?.continueDrag() },
            endDrag: { [weak self] in self?.endDrag() },
            resizeByMouse: { [weak self] in self?.continueResize() },
            endResize: { [weak self] in self?.endResize() },
            addFiles: { [weak self] in self?.presentAddPanel() },
            deleteBox: { [weak self] in self?.confirmDelete() },
            newBox: { [weak self] in self?.createSiblingBox() },
            handleDrop: { [weak self] urls in self?.handleDrop(urls) },
            openItem: { FileActions.open($0) },
            revealItem: { [weak self] url in self?.revealKeepingVisibility(url) },
            copyItemPath: { FileActions.copyPath($0) },
            openInEditor: { FileActions.openInCodeEditor($0) },
            editorName: FileActions.preferredEditorName ?? "",
            openInTerminal: { FileActions.openInTerminal($0) },
            removeItem: { Commands.remove([$0], from: self.boxID) },
            trashItem: { [weak self] url in self?.confirmTrash(url) },
            toggleItemHidden: { id, hidden in
                Commands.toggleHidden(hidden, itemID: id, in: self.boxID)
            },
            updateTileFrames: { [weak self] tiles, order in
                guard let self else { return }
                let changed = self.dropContainer.tiles.count != tiles.count
                self.dropContainer.tiles = tiles
                self.dropContainer.orderedItemIDs = order
                if changed {
                    let folders = tiles.values.filter(\.isDirectory).count
                    self.dropContainer.note("几何上报 \(tiles.count) 个格子（其中文件夹 \(folders) 个）")
                }
            },
            clearItems: { [weak self] in self?.confirmClear() }
        )
    }

    // MARK: 生命周期

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    /// 淡入出现，避免窗口「啪」地一下蹦出来。
    func showAnimated() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// 淡出后再真正隐藏。
    func hideAnimated(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
            completion?()
        }
    }

    func close() {
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
    }

    /// 把整理框临时提到最前，几秒后再落回配置的层级。
    /// 用于「定位」：在框被别的窗口盖住时把它捞出来。
    func summon() {
        let configured = box.floatOnTop ? NSWindow.Level.floating : Self.normalLevel
        summonWorkItem?.cancel()
        panel.level = .floating
        panel.orderFrontRegardless()
        flash()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.level = configured
            // 落回桌面层后仍要保证它是该层里靠前的
            self.panel.orderFrontRegardless()
        }
        summonWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }

    func flash() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0.3
        } completionHandler: { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                self?.panel.animator().alphaValue = 1.0
            }
        }
    }

    func apply(_ newBox: BoxConfig) {
        box = newBox
        let targetLevel: NSWindow.Level = newBox.floatOnTop ? .floating : Self.normalLevel
        if panel.level != targetLevel { panel.level = targetLevel }

        if !isAdjustingFrame, dragStartFrame == nil, resizeStartFrame == nil {
            let target = LayoutEngine.sanitize(newBox.frame, minSize: Self.minSize)
            if !Self.framesAlmostEqual(panel.frame, target) {
                isAdjustingFrame = true
                panel.setFrame(target, display: true)
                isAdjustingFrame = false
            }
        }
    }

    // MARK: 拖动（带吸附与引导线）

    private func continueDrag() {
        guard !isAdjustingFrame else { return }
        let mouse = NSEvent.mouseLocation

        if dragStartFrame == nil {
            let current = panel.frame
            dragStartFrame = current
            dragMouseOffset = CGPoint(x: mouse.x - current.origin.x, y: mouse.y - current.origin.y)
            ui.isDragging = true
        }
        guard let offset = dragMouseOffset, let start = dragStartFrame else { return }

        let proposed = CGRect(
            x: mouse.x - offset.x,
            y: mouse.y - offset.y,
            width: start.width,
            height: start.height
        )

        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? proposed
        let others = BoxWindowManager.shared.frames(excluding: boxID)
        let snapped = SnapEngine.snap(moving: proposed, others: others, screen: visible)

        panel.setFrame(CGRect(origin: snapped.origin, size: proposed.size), display: true)

        if let screen {
            BoxWindowManager.shared.showGuides(snapped.guides, on: screen)
        }
    }

    private func endDrag() {
        guard dragStartFrame != nil else { return }
        dragStartFrame = nil
        dragMouseOffset = nil
        ui.isDragging = false
        BoxWindowManager.shared.hideGuides()
        persistFrame()
    }

    // MARK: 缩放

    private func continueResize() {
        guard !isAdjustingFrame else { return }
        let mouse = NSEvent.mouseLocation
        if resizeStartFrame == nil {
            resizeStartFrame = panel.frame
            resizeStartMouse = mouse
        }
        guard let start = resizeStartFrame, let mouse0 = resizeStartMouse else { return }

        let dx = mouse.x - mouse0.x
        let dy = mouse.y - mouse0.y
        var frame = start
        let newWidth = max(Self.minSize.width, start.width + dx)
        // 屏幕坐标 y 向上：往下拖 dy 为负，高度应当变大，所以是减不是加
        let newHeight = max(Self.minSize.height, start.height - dy)
        frame.size = CGSize(width: newWidth, height: newHeight)
        frame.origin.x = start.minX
        frame.origin.y = start.maxY - newHeight      // 固定左上角

        // 缩放吸附：右边缘和下边缘对齐到屏幕 / 其它整理框，并显示引导线
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? frame
        let others = BoxWindowManager.shared.frames(excluding: boxID)
        let snapped = SnapEngine.snapResize(
            frame: frame, others: others, screen: visible, minSize: Self.minSize
        )
        frame.size = snapped.size
        frame.origin.y = start.maxY - snapped.size.height   // 依旧固定左上角

        panel.setFrame(frame, display: true)

        if let screen, !snapped.guides.isEmpty {
            BoxWindowManager.shared.showGuides(snapped.guides, on: screen)
        } else {
            BoxWindowManager.shared.hideGuides()
        }
    }

    private func endResize() {
        guard resizeStartFrame != nil else { return }
        resizeStartFrame = nil
        resizeStartMouse = nil
        BoxWindowManager.shared.hideGuides()
        persistFrame()
    }

    // MARK: 位置持久化

    private func schedulePersistFrame() {
        guard !isAdjustingFrame, dragStartFrame == nil, resizeStartFrame == nil else { return }
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persistFrame() }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func persistFrame() {
        let frame = panel.frame
        store.update(id: boxID) { $0.frame = frame }
    }

    private static func framesAlmostEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 0.5 && abs(a.origin.y - b.origin.y) < 0.5 &&
        abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    // MARK: 条目操作（全部只加引用，不搬文件）

    private func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        withAnimation { Commands.add(urls, to: boxID) }
    }

    private func presentAddPanel() {
        let urls = FileActions.pickFiles(
            message: "选择要收进「\(box.name)」的内容",
            startingAt: nil
        )
        guard !urls.isEmpty else { return }
        handleDrop(urls)
    }

    private func createSiblingBox() {
        Commands.createBox()
    }

    /// 隐藏的文件在访达里是选不中的，所以先恢复显示再定位。
    ///
    /// 注意这是**真的把它变成可见**，并且同步更新记录 —— 早先只取消隐藏标志、
    /// 不同步记录，配置里还写着「我隐藏过它」，状态就对不上了。
    /// 想再藏起来，用条目菜单里的「隐藏原文件」。
    private func revealKeepingVisibility(_ url: URL) {
        if HiddenFlag.isHidden(url) {
            Store.shared.setPathHidden(false, path: url.path)
            BoxWindowManager.shared.refresh(boxID: boxID)
        }
        FileActions.reveal(url)
    }

    private func confirmClear() {
        Commands.confirmAndClearBox(boxID)
    }

    private func confirmTrash(_ url: URL) {
        guard FileActions.confirm(
            title: "把「\(url.lastPathComponent)」移到废纸篓？",
            message: "可以从废纸篓恢复。",
            confirmTitle: "移到废纸篓"
        ) else { return }
        if FileActions.moveToTrash(url) {
            BoxWindowManager.shared.refresh(boxID: boxID)
        }
    }

    /// 点选 / ⌘点选 / ⇧范围选。修饰键由 AppKit 侧原样传进来。
    private func applySelection(to itemID: UUID, flags: NSEvent.ModifierFlags) {
        let order = itemsModel.items.map(\.id)
        if flags.contains(.command) {
            if ui.selectedItemIDs.contains(itemID) {
                ui.selectedItemIDs.remove(itemID)
            } else {
                ui.selectedItemIDs.insert(itemID)
                ui.selectionAnchor = itemID
            }
        } else if flags.contains(.shift),
                  let anchor = ui.selectionAnchor,
                  let anchorIndex = order.firstIndex(of: anchor),
                  let targetIndex = order.firstIndex(of: itemID) {
            let range = anchorIndex <= targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
            ui.selectedItemIDs = Set(order[range])
        } else {
            ui.selectedItemIDs = [itemID]
            ui.selectionAnchor = itemID
        }
    }

    private func confirmDelete() {
        Commands.confirmAndDeleteBox(boxID)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { schedulePersistFrame() }
    func windowDidResize(_ notification: Notification) { schedulePersistFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { persistFrame() }
}
