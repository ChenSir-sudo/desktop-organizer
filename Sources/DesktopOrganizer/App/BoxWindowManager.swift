import AppKit
import Combine
import SwiftUI

/// 无边框、可浮动的整理框面板。
final class BoxPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 负责让「配置里的整理框」和「屏幕上的窗口」保持一致。
final class BoxWindowManager {
    static let shared = BoxWindowManager()

    private var controllers: [UUID: BoxWindowController] = [:]
    private var hiddenIDs = Set<UUID>()
    private let guideOverlay = GuideOverlayWindow()
    private var cancellables = Set<AnyCancellable>()
    private var dragOutTimer: Timer?

    private init() {
        // 拖到任何整理框之外松手 = 把它从框里拿出来（原文件恢复显示）
        DragSession.shared.$payload
            .compactMap { $0 }
            .sink { [weak self] payload in self?.armDragOutWatch(payload) }
            .store(in: &cancellables)
    }

    /// 拖拽会话会吞掉鼠标事件，`addLocalMonitorForEvents(.leftMouseUp)` 收不到，
    /// 所以改成轮询按键状态 —— 松开的那一刻就是拖拽结束。
    private func armDragOutWatch(_ payload: DragPayload) {
        disarmDragOutWatch()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard NSEvent.pressedMouseButtons == 0 else { return }
            timer.invalidate()
            self.dragOutTimer = nil
            // 让 DropDelegate / onDrop 先把「被接住」的状态写完
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                let session = DragSession.shared
                defer { session.finish() }
                guard !session.handled else { return }
                guard !self.containsScreenPoint(NSEvent.mouseLocation) else { return }
                // 从框里摘掉即可 —— 文件在拖拽开始时就已恢复显示，
                // 若被访达移进了别的目录，它现在是可见的，不需要我们再动。
                let paths = payload.itemIDs.compactMap { id in
                    Store.shared.box(id: payload.boxID)?.items.first { $0.id == id }?.path
                }
                OperationsLog.append("拖出整理框，解除引用 \(payload.itemIDs.count) 个: \(paths.joined(separator: ", "))")
                Store.shared.removeItems(Set(payload.itemIDs), from: payload.boxID)
                self.refreshAll()
                self.removeFinderClippingFiles(matching: payload)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragOutTimer = timer
    }

    private func disarmDragOutWatch() {
        dragOutTimer?.invalidate()
        dragOutTimer = nil
    }

    /// 把条目拖到访达/桌面时，系统可能按「剪贴文件」把拖拽载荷原样写成一个小文件。
    /// 这里把它清掉：判据是**文件内容完全等于刚才那份拖拽载荷**，且是刚刚创建的 ——
    /// 内容精确匹配，不会误删任何正常文件。
    private func removeFinderClippingFiles(matching payload: DragPayload) {
        let needle = Data(payload.encoded.utf8)
        let desktop = AppPaths.desktopDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: desktop.path) else { return }

        for name in names {
            let url = desktop.appendingPathComponent(name)
            guard !url.fileInfo.isDirectory else { continue }
            guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  Date().timeIntervalSince(created) < 20 else { continue }
            guard let data = try? Data(contentsOf: url), data == needle else { continue }
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            OperationsLog.append("清掉访达剪贴文件: \(url.path)")
            NSLog("[桌面整理] 清掉访达生成的剪贴文件：%@", name)
        }
    }

    /// 屏幕坐标是否落在任何一个整理框窗口里。
    func containsScreenPoint(_ point: CGPoint) -> Bool {
        controllers.values.contains { $0.panel.isVisible && $0.panel.frame.contains(point) }
    }

    var count: Int { controllers.count }

    var allBoxes: [BoxConfig] { Store.shared.boxes }

    func sync(_ boxes: [BoxConfig]) {
        let ids = Set(boxes.map(\.id))

        for (id, controller) in controllers where !ids.contains(id) {
            controller.close()
            controllers.removeValue(forKey: id)
            hiddenIDs.remove(id)
        }

        for box in boxes {
            if let controller = controllers[box.id] {
                controller.apply(box)
            } else {
                let controller = BoxWindowController(box: box)
                controllers[box.id] = controller
                if !hiddenIDs.contains(box.id) { controller.showAnimated() }
            }
        }
    }

    func showAll() {
        hiddenIDs.removeAll()
        for controller in controllers.values where !controller.panel.isVisible {
            controller.showAnimated()
        }
    }

    func hideAll() {
        for (id, controller) in controllers {
            controller.hideAnimated()
            hiddenIDs.insert(id)
        }
    }

    var allHidden: Bool {
        !controllers.isEmpty && hiddenIDs.count == controllers.count
    }

    func isHidden(id: UUID) -> Bool { hiddenIDs.contains(id) }

    func setHidden(_ hidden: Bool, id: UUID) {
        guard let controller = controllers[id] else { return }
        if hidden {
            controller.hideAnimated()
            hiddenIDs.insert(id)
        } else {
            hiddenIDs.remove(id)
            controller.showAnimated()
        }
    }

    func toggleVisibility() {
        if allHidden { showAll() } else { hideAll() }
    }

    /// 只刷新某一个整理框的内容。
    func refresh(boxID: UUID) {
        controllers[boxID]?.itemsModel.refresh(force: true)
    }

    func refreshAll() {
        for controller in controllers.values {
            controller.itemsModel.refresh(force: true)
        }
    }

    /// 定位到某个整理框：如果是被隐藏的，先显示；然后临时提到最前，方便找到它。
    func focus(id: UUID) {
        guard let controller = controllers[id] else { return }
        hiddenIDs.remove(id)
        controller.summon()
    }

    func controller(for id: UUID) -> BoxWindowController? { controllers[id] }

    func closeAll() {
        for controller in controllers.values { controller.close() }
        controllers.removeAll()
        hiddenIDs.removeAll()
    }

    // MARK: 吸附辅助

    /// 其它整理框的窗口范围，用于对齐吸附。
    func frames(excluding id: UUID) -> [CGRect] {
        controllers.compactMap { key, controller in
            guard key != id, !hiddenIDs.contains(key), controller.panel.isVisible else { return nil }
            return controller.panel.frame
        }
    }

    func showGuides(_ guides: [GuideLine], on screen: NSScreen) {
        guideOverlay.show(guides: guides, on: screen)
    }

    func hideGuides() {
        guideOverlay.hide()
    }
}
