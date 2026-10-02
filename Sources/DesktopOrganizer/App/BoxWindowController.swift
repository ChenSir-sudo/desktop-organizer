import AppKit

/// 整理框窗口。
///
/// 新方案里它**不是装文件的容器**，而是桌面上的一块**边框区域**：
/// - 窗口完全透明，只画一圈边框和标题（`BoxFrameView`）
/// - 中间不接收鼠标 → 用户照样能在框内正常拖动、双击、右键桌面图标
/// - 只有**边框那一圈**能抓来拖动，四角能缩放
/// - 挂在桌面图层：壁纸与图标之上、普通应用窗口之下
///
/// **程序不碰用户的文件。** 这里唯一会写的只有窗口坐标（存进配置）；
/// 摆图标位置只发生在用户主动点「整理框内图标」时，走 `DesktopIcons`。
final class BoxWindowController {

    static let minSize = CGSize(width: 180, height: 140)

    let panel: BoxPanel
    private let frameView = BoxFrameView(frame: .zero)
    private(set) var boxID: UUID

    private var box: BoxConfig
    private var dragOrigin: CGPoint?
    private var dragMouseOffset: CGPoint?
    private var resizeEdge: ResizeEdge?
    private var resizeStartFrame: CGRect?
    private var resizeStartMouse: CGPoint?
    private var interactTimer: Timer?
    private var summonWorkItem: DispatchWorkItem?

    /// 边框的图层：在桌面图标之上（框能画在图标上），又在普通窗口之下（不挡工作）。
    static var frameLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    enum ResizeEdge { case topLeft, topRight, bottomLeft, bottomRight }

    init(box: BoxConfig) {
        self.box = box
        self.boxID = box.id

        panel = BoxPanel(
            contentRect: LayoutEngine.sanitize(box.frame, minSize: Self.minSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = Self.frameLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        frameView.frame = CGRect(origin: .zero, size: panel.frame.size)
        frameView.autoresizingMask = [.width, .height]
        frameView.controller = self
        panel.contentView = frameView

        apply(box)
    }

    // MARK: 与 Store 同步

    func apply(_ newBox: BoxConfig) {
        box = newBox
        frameView.title = newBox.name
        frameView.accent = NSColor(hex: newBox.accentHex)
        let target = LayoutEngine.sanitize(newBox.frame, minSize: Self.minSize)
        if panel.frame != target {
            panel.setFrame(target, display: true)
        }
        refreshMemberCount()
    }

    /// 框里现在有多少个桌面图标 —— 实时按坐标算，**不存任何东西**。
    func refreshMemberCount() {
        let frame = panel.frame
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let icons = DesktopIcons.readAll()
            let count = DesktopArranger.icons(in: frame, from: icons).count
            DispatchQueue.main.async { self?.frameView.memberCount = count }
        }
    }

    // MARK: 显隐

    func showAnimated() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 1
        }
    }

    func hideAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        })
    }

    func close() { panel.orderOut(nil) }

    /// 把框临时提到最前几秒，方便找到它，然后落回桌面图层。
    func summon() {
        summonWorkItem?.cancel()
        let original = Self.frameLevel
        panel.level = .floating
        panel.orderFrontRegardless()
        frameView.isSelected = true
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.level = original
            self.frameView.isSelected = false
            self.panel.orderFrontRegardless()
        }
        summonWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: item)
    }

    // MARK: 拖动 / 缩放

    /// 从边框按下：判断是拖动还是缩放。
    func beginInteraction(at point: CGPoint) {
        let grip = BoxFrameView.edgeGrip
        let top = point.y > panel.frame.height - grip
        let bottom = point.y < grip
        let left = point.x < grip
        let right = point.x > panel.frame.width - grip

        if (top || bottom) && left {
            resizeEdge = top ? .topLeft : .bottomLeft
            resizeStartFrame = panel.frame
            resizeStartMouse = NSEvent.mouseLocation
        } else if (top || bottom) && right {
            resizeEdge = top ? .topRight : .bottomRight
            resizeStartFrame = panel.frame
            resizeStartMouse = NSEvent.mouseLocation
        } else {
            dragOrigin = panel.frame.origin
            dragMouseOffset = NSEvent.mouseLocation
        }
        startInteractionTimer()
    }

    /// 用定时器跟随鼠标：拖动/缩放期间拿不到鼠标捕获，轮询最稳。
    private func startInteractionTimer() {
        interactTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if NSEvent.pressedMouseButtons == 0 {
                timer.invalidate()
                self.interactTimer = nil
                self.endInteraction()
                return
            }
            self.continueInteraction()
        }
        RunLoop.main.add(timer, forMode: .common)
        interactTimer = timer
    }

    private func continueInteraction() {
        if resizeEdge != nil { continueResize() } else if dragOrigin != nil { continueDrag() }
    }

    private func endInteraction() {
        let wasActive = dragOrigin != nil || resizeEdge != nil
        dragOrigin = nil
        dragMouseOffset = nil
        resizeEdge = nil
        resizeStartFrame = nil
        resizeStartMouse = nil
        BoxWindowManager.shared.hideGuides()
        if wasActive {
            persistFrame()
            refreshMemberCount()
        }
    }

    private func continueDrag() {
        guard let start = dragOrigin, let mouse0 = dragMouseOffset else { return }
        let mouse = NSEvent.mouseLocation
        let proposed = CGRect(x: start.x + (mouse.x - mouse0.x),
                              y: start.y + (mouse.y - mouse0.y),
                              width: panel.frame.width, height: panel.frame.height)
        let screen = panel.screen ?? NSScreen.main
        let snapped = SnapEngine.snap(
            moving: proposed,
            others: BoxWindowManager.shared.frames(excluding: boxID),
            screen: screen?.visibleFrame ?? proposed
        )
        panel.setFrame(CGRect(origin: snapped.origin, size: proposed.size), display: true)
        if let screen, !snapped.guides.isEmpty {
            BoxWindowManager.shared.showGuides(snapped.guides, on: screen)
        } else {
            BoxWindowManager.shared.hideGuides()
        }
    }

    private func continueResize() {
        guard let edge = resizeEdge, let start = resizeStartFrame, let mouse0 = resizeStartMouse else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - mouse0.x
        let dy = mouse.y - mouse0.y

        var frame = start
        switch edge {
        case .topRight:
            frame.size.width = max(Self.minSize.width, start.width + dx)
            frame.size.height = max(Self.minSize.height, start.height + dy)
        case .topLeft:
            frame.size.width = max(Self.minSize.width, start.width - dx)
            frame.size.height = max(Self.minSize.height, start.height + dy)
        case .bottomRight:
            frame.size.width = max(Self.minSize.width, start.width + dx)
            frame.size.height = max(Self.minSize.height, start.height - dy)
        case .bottomLeft:
            frame.size.width = max(Self.minSize.width, start.width - dx)
            frame.size.height = max(Self.minSize.height, start.height - dy)
        }

        let screen = panel.screen ?? NSScreen.main
        let snapped = SnapEngine.snapResize(
            frame: frame,
            others: BoxWindowManager.shared.frames(excluding: boxID),
            screen: screen?.visibleFrame ?? frame,
            minSize: Self.minSize
        )
        frame.size = snapped.size
        // 固定住不被拖的那两条边
        if edge == .topLeft || edge == .bottomLeft { frame.origin.x = start.maxX - frame.width }
        if edge == .topLeft || edge == .topRight { frame.origin.y = start.maxY - frame.height }

        panel.setFrame(frame, display: true)
        if let screen, !snapped.guides.isEmpty {
            BoxWindowManager.shared.showGuides(snapped.guides, on: screen)
        } else {
            BoxWindowManager.shared.hideGuides()
        }
    }

    private func persistFrame() {
        let frame = panel.frame
        Store.shared.update(id: boxID) { $0.frame = frame }
    }

    // MARK: 动作

    /// 把这个框里的图标摆整齐。返回摆好的个数。
    @discardableResult
    func tidyIcons() -> Int {
        let placed = DesktopArranger.tidy(panel.frame)
        refreshMemberCount()
        OperationsLog.append("整理框「\(box.name)」：摆好 \(placed) 个图标（只动位置，不碰文件）")
        return placed
    }

    @discardableResult
    func rename(to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        box.name = trimmed
        frameView.title = trimmed
        Store.shared.update(id: boxID) { $0.name = trimmed }
        return true
    }

    var currentFrame: CGRect { panel.frame }
    var memberCount: Int { frameView.memberCount }
}
