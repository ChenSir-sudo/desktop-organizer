import AppKit

/// 负责让「配置里的整理框」和「屏幕上的窗口」保持一致。
final class BoxWindowManager {
    static let shared = BoxWindowManager()

    private var controllers: [UUID: BoxWindowController] = [:]
    private var hiddenIDs = Set<UUID>()

    private init() {}

    var count: Int { controllers.count }

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
                if !hiddenIDs.contains(box.id) {
                    controller.show()
                }
            }
        }
    }

    func showAll() {
        hiddenIDs.removeAll()
        for controller in controllers.values {
            controller.show()
        }
    }

    func hideAll() {
        for (id, controller) in controllers {
            controller.hide()
            hiddenIDs.insert(id)
        }
    }

    var allHidden: Bool {
        !controllers.isEmpty && hiddenIDs.count == controllers.count
    }

    func toggleVisibility() {
        if allHidden { showAll() } else { hideAll() }
    }

    func refreshAll() {
        for controller in controllers.values {
            controller.folderModel.refresh(force: true)
        }
    }

    func focus(id: UUID) {
        guard let controller = controllers[id] else { return }
        hiddenIDs.remove(id)
        controller.flash()
    }

    func controller(for id: UUID) -> BoxWindowController? {
        controllers[id]
    }

    func closeAll() {
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
        hiddenIDs.removeAll()
    }
}
