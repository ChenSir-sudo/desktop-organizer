import AppKit
import Combine
import SwiftUI

final class BoxWindowController: NSObject, NSWindowDelegate {

    static let settingsDelta: CGFloat = 322
    static let minSize = CGSize(width: 230, height: 210)

    private let store = Store.shared
    private(set) var boxID: UUID
    let panel: BoxPanel
    private(set) var folderModel: FolderModel
    let uiState = BoxUIState()
    private var hostView: NSHostingView<AnyView>
    private var cancellables = Set<AnyCancellable>()
    private var box: BoxConfig

    // 拖动 / 缩放过程中的临时状态
    private var dragStartFrame: CGRect?
    private var dragMouseOffset: CGPoint?
    private var resizeStartFrame: CGRect?
    private var resizeStartMouse: CGPoint?

    private var isAdjustingFrame = false
    private var settingsExpanded = false
    private var persistWorkItem: DispatchWorkItem?

    init(box: BoxConfig) {
        self.box = box
        self.boxID = box.id
        self.folderModel = FolderModel(folder: box.folderURL)
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

        // 界面状态 → 窗口尺寸：无论是点齿轮还是菜单触发，都走同一条路径
        uiState.$settingsOpen
            .removeDuplicates()
            .sink { [weak self] open in self?.setSettings(open) }
            .store(in: &cancellables)
    }

    // MARK: 初始化

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // 阴影交给 SwiftUI 画，避免方角阴影
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.minSize = Self.minSize
        panel.level = box.floatOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let safeFrame = LayoutEngine.sanitize(box.frame, minSize: Self.minSize)
        panel.setFrame(safeFrame, display: false)
        panel.contentView = hostView
        hostView.autoresizingMask = [.width, .height]
    }

    private func buildContent() {
        hostView.rootView = AnyView(
            BoxView(model: folderModel, uiState: uiState, boxID: boxID, actions: makeActions())
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
            handleDrop: { [weak self] urls in self?.handleDrop(urls) },
            chooseFolder: { [weak self] in self?.presentFolderPicker() },
            revealFolder: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.activateFileViewerSelecting([self.box.folderURL])
            },
            openItem: { url in
                NSWorkspace.shared.open(url)
            },
            revealItem: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            moveItemToDesktop: { [weak self] url in
                self?.move([url], into: AppPaths.desktopDirectory)
            },
            moveItemToTrash: { [weak self] url in
                self?.confirmTrash(url)
            }
        )
    }

    // MARK: 生命周期

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
    }

    func flash() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0.35
        } completionHandler: { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                self?.panel.animator().alphaValue = 1.0
            }
        }
    }

    /// Store 变化时同步窗口状态
    func apply(_ newBox: BoxConfig) {
        let newFolder = newBox.folderURL.standardizedFileURL
        let folderChanged = newFolder != folderModel.folder.standardizedFileURL
        box = newBox

        let targetLevel: NSWindow.Level = newBox.floatOnTop ? .floating : .normal
        if panel.level != targetLevel {
            panel.level = targetLevel
        }

        if folderChanged {
            folderModel = FolderModel(folder: newBox.folderURL)
            buildContent()
        }

        if !isAdjustingFrame, dragStartFrame == nil, resizeStartFrame == nil {
            let target = LayoutEngine.sanitize(displayFrame(from: newBox.frame), minSize: panel.minSize)
            if !framesAlmostEqual(panel.frame, target) {
                isAdjustingFrame = true
                panel.setFrame(target, display: true)
                isAdjustingFrame = false
            }
        }
    }

    /// 配置里存的是「设置面板收起」时的基准帧；展开时要在显示帧上补上高度差，顶边保持不动。
    private func displayFrame(from base: CGRect) -> CGRect {
        var frame = base
        if settingsExpanded {
            frame.size.height += Self.settingsDelta
            frame.origin.y -= Self.settingsDelta
        }
        return frame
    }

    // MARK: 拖动

    private func continueDrag() {
        guard !isAdjustingFrame else { return }
        let mouse = NSEvent.mouseLocation
        if dragStartFrame == nil {
            let current = panel.frame
            dragStartFrame = current
            dragMouseOffset = CGPoint(x: mouse.x - current.origin.x, y: mouse.y - current.origin.y)
        }
        guard let offset = dragMouseOffset else { return }
        var frame = panel.frame
        frame.origin.x = mouse.x - offset.x
        frame.origin.y = mouse.y - offset.y
        panel.setFrame(frame, display: true)
    }

    private func endDrag() {
        guard dragStartFrame != nil else { return }
        dragStartFrame = nil
        dragMouseOffset = nil
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
        let minHeight = Self.minSize.height + (settingsExpanded ? Self.settingsDelta : 0)

        var frame = start
        let newWidth = max(Self.minSize.width, start.width + dx)
        let newHeight = max(minHeight, start.height - dy)
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

    // MARK: 外观设置面板

    func toggleSettingsPanel() {
        uiState.settingsOpen.toggle()
    }

    var isSettingsPanelOpen: Bool { settingsExpanded }

    private func setSettings(_ open: Bool) {
        guard settingsExpanded != open else { return }
        settingsExpanded = open
        isAdjustingFrame = true
        panel.minSize = CGSize(
            width: Self.minSize.width,
            height: Self.minSize.height + (open ? Self.settingsDelta : 0)
        )

        var frame = panel.frame
        if open {
            frame.size.height += Self.settingsDelta
            frame.origin.y -= Self.settingsDelta
            NSApp.activate(ignoringOtherApps: true)
        } else {
            frame.size.height = max(Self.minSize.height, frame.size.height - Self.settingsDelta)
            frame.origin.y += Self.settingsDelta
        }
        panel.setFrame(frame, display: true, animate: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isAdjustingFrame = false
            self?.persistFrame()
        }
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
        var frame = panel.frame
        if settingsExpanded {
            // 存的是「收起设置」时的高度，重新打开时才能还原
            frame.size.height -= Self.settingsDelta
            frame.origin.y += Self.settingsDelta
        }
        store.update(id: boxID) { $0.frame = frame }
    }

    private func framesAlmostEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.origin.x - b.origin.x) < 0.5 &&
        abs(a.origin.y - b.origin.y) < 0.5 &&
        abs(a.width - b.width) < 0.5 &&
        abs(a.height - b.height) < 0.5
    }

    // MARK: 文件操作

    private func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let result = FileMover.move(urls, into: box.folderURL)
        folderModel.refresh(force: true)

        if !result.failures.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "有 \(result.failures.count) 个文件没有移动成功"
            alert.informativeText = result.failures.prefix(8)
                .map { "\($0.url.lastPathComponent)：\($0.reason)" }
                .joined(separator: "\n")
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func move(_ urls: [URL], into folder: URL) {
        _ = FileMover.move(urls, into: folder)
        folderModel.refresh(force: true)
    }

    private func confirmTrash(_ url: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "把「\(url.lastPathComponent)」移到废纸篓？"
        alert.informativeText = "可以从废纸篓恢复。"
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        folderModel.refresh(force: true)
    }

    private func presentAddPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "整理"
        panel.message = "选择要移入「\(box.name)」的内容"
        panel.directoryURL = AppPaths.desktopDirectory
        if panel.runModal() == .OK {
            handleDrop(panel.urls)
        }
    }

    private func presentFolderPicker() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "使用此文件夹"
        panel.message = "选择「\(box.name)」对应的文件夹"
        panel.directoryURL = box.folderURL
        if panel.runModal() == .OK, let url = panel.url {
            store.update(id: boxID) { $0.folderPath = url.path }
        }
    }

    private func confirmDelete() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除整理框「\(box.name)」？"
        alert.informativeText = "框里的 \(folderModel.totalCount) 个文件不会被删除，仍然保存在：\n\(box.folderURL.path)"
        alert.addButton(withTitle: "删除整理框")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Store.shared.removeBox(id: boxID)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        schedulePersistFrame()
    }

    func windowDidResize(_ notification: Notification) {
        schedulePersistFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrame()
    }
}
