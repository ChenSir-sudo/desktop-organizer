import AppKit
import Combine
import SwiftUI

final class BoxWindowController: NSObject, NSWindowDelegate {

    static let minSize = CGSize(width: 230, height: 210)

    /// 桌面图标层：在壁纸和桌面图标之上、在所有应用窗口之下。
    static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
    }

    private let store = Store.shared
    private(set) var boxID: UUID
    let panel: BoxPanel
    private(set) var itemsModel: BoxItemsModel
    let ui = BoxUIState()

    private var hostView: NSHostingView<AnyView>
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
        panel.level = box.floatOnTop ? .floating : Self.desktopLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.setFrame(LayoutEngine.sanitize(box.frame, minSize: Self.minSize), display: false)
        panel.contentView = hostView
        hostView.autoresizingMask = [.width, .height]
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
    ///
    /// 桌面层的框会被任何应用窗口盖住 —— 没有这个机制的话，一旦被盖住就再也
    /// 够不着它了（既点不中，也没法通过拖动露出来）。菜单栏的「整理框」列表和
    /// 主窗口卡片上的「定位」都会走这里。
    func summon() {
        let configured = box.floatOnTop ? NSWindow.Level.floating : Self.desktopLevel
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
        let targetLevel: NSWindow.Level = newBox.floatOnTop ? .floating : Self.desktopLevel
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
        panel.setFrame(frame, display: true)
    }

    private func endResize() {
        guard resizeStartFrame != nil else { return }
        resizeStartFrame = nil
        resizeStartMouse = nil
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

    private func confirmDelete() {
        Commands.confirmAndDeleteBox(boxID)
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { schedulePersistFrame() }
    func windowDidResize(_ notification: Notification) { schedulePersistFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { persistFrame() }
}
