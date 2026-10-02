import AppKit
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

    private init() {}

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

    func refreshAll() {
        for controller in controllers.values {
            controller.itemsModel.refresh(force: true)
        }
    }

    func focus(id: UUID) {
        guard let controller = controllers[id] else { return }
        hiddenIDs.remove(id)
        controller.flash()
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
