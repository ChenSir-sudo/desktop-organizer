import AppKit

/// 界面层调用的高层命令。
///
/// 收在这一层有两个原因：
/// 1. 同一个动作（删除整理框、按类型归类桌面）原本在整理框面板和主窗口各写了一遍；
/// 2. 条目改动之后「要刷新哪些 model」的口径原本散在各个视图里，
///    改一次刷新策略得同时改五处。现在视图只调这里的一个方法。
enum Commands {

    // MARK: 整理框

    @discardableResult
    static func createBox() -> BoxConfig {
        let box = Store.shared.addBox()
        BoxWindowManager.shared.sync(Store.shared.boxes)
        BoxWindowManager.shared.focus(id: box.id)
        return box
    }

    /// 删除整理框（先确认）。框内文件会恢复原位置显示。
    @discardableResult
    static func confirmAndDeleteBox(_ id: UUID) -> Bool {
        guard let box = Store.shared.box(id: id) else { return false }
        let count = box.items.count
        let message = count == 0 ? "框里没有条目。" : "框内 \(count) 个文件会恢复显示。"
        guard FileActions.confirm(
            title: "删除整理框「\(box.name)」？",
            message: message,
            confirmTitle: "删除整理框"
        ) else { return false }

        Store.shared.removeBox(id: id)
        return true
    }

    static func confirmAndClearBox(_ id: UUID) {
        guard let box = Store.shared.box(id: id), !box.items.isEmpty else { return }
        guard FileActions.confirm(
            title: "清空「\(box.name)」里的 \(box.items.count) 个条目？",
            message: "移除后这些文件会恢复显示。",
            confirmTitle: "清空"
        ) else { return }
        Store.shared.removeAllItems(from: id)
        BoxWindowManager.shared.refresh(boxID: id)
    }

    // MARK: 桌面归类

    static func categorizeDesktop() {
        let store = Store.shared
        let groups = DeskCategorizer.scanDesktop()
        let total = groups.values.reduce(0) { $0 + $1.count }

        guard total > 0 else {
            FileActions.info(title: "桌面很干净", message: "没有找到需要归类的东西。")
            return
        }

        if store.prefs.confirmBeforeCategorize {
            let detail = FileCategory.allCases.compactMap { category -> String? in
                guard let urls = groups[category], !urls.isEmpty else { return nil }
                return "\(category.rawValue)  \(urls.count) 项"
            }.joined(separator: "\n")
            guard FileActions.confirm(
                title: "把桌面上的 \(total) 项按类型收进整理框？",
                message: detail + "\n\n文件不会被移动，只是被整理框引用。",
                confirmTitle: "开始归类"
            ) else { return }
        }

        let outcome = DeskCategorizer.categorizeIntoBoxes()
        BoxWindowManager.shared.sync(store.boxes)
        BoxWindowManager.shared.showAll()
        FileActions.info(title: "归类完成", message: outcome.summary)
    }

    // MARK: 条目改动

    static func add(_ urls: [URL], to boxID: UUID, at position: Int? = nil) {
        guard Store.shared.addItems(urls, to: boxID, at: position) > 0 else { return }
        BoxWindowManager.shared.refresh(boxID: boxID)
    }

    static func remove(_ ids: Set<UUID>, from boxID: UUID) {
        guard !ids.isEmpty else { return }
        Store.shared.removeItems(ids, from: boxID)
        BoxWindowManager.shared.refresh(boxID: boxID)
    }

    static func reorder(in boxID: UUID, itemIDs: [UUID], to index: Int) {
        Store.shared.moveItems(in: boxID, itemIDs: itemIDs, to: index)
        rehideAfterDrop(itemIDs, in: boxID)
        BoxWindowManager.shared.refresh(boxID: boxID)
    }

    static func transfer(itemIDs: [UUID], from source: UUID, to target: UUID, at index: Int) {
        guard Store.shared.transferItems(itemIDs, from: source, to: target, at: index) else { return }
        rehideAfterDrop(itemIDs, in: target)
        BoxWindowManager.shared.refresh(boxID: source)
        BoxWindowManager.shared.refresh(boxID: target)
    }

    /// 把框内条目对应的文件移进某个目录（拖到文件夹图标上）。
    /// 文件离开了整理框的管辖范围，所以先把条目从框里摘掉（顺带恢复原位置显示），再搬。
    static func moveItemsIntoFolder(_ itemIDs: [UUID], in boxID: UUID, folder: URL) {
        guard let box = Store.shared.box(id: boxID) else { return }
        let targets = box.items.filter { itemIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        // **先搬，再按结果摘条目。** 反过来会在搬移失败时白白丢掉条目
        // （文件没搬走，条目却没了，用户看到的是"东西消失了"）。
        let outcome = FileActions.move(targets.map(\.url), into: folder)
        let succeeded = Set(outcome.moved.map { $0.from.standardizedFileURL.path })
        let removeIDs = targets
            .filter { succeeded.contains($0.url.standardizedFileURL.path) }
            .map(\.id)
        if !removeIDs.isEmpty {
            Store.shared.removeItems(Set(removeIDs), from: boxID)
        }

        BoxWindowManager.shared.refresh(boxID: boxID)
        BoxWindowManager.shared.refreshAll()

        if !outcome.failures.isEmpty {
            FileActions.info(
                title: "有 \(outcome.failures.count) 项没能移入「\(folder.lastPathComponent)」",
                message: outcome.failures.map { "\($0.url.lastPathComponent)：\($0.reason)" }.joined(separator: "\n")
            )
        }
    }

    /// 拖拽开始前把条目对应的文件恢复显示。
    ///
    /// 必须这么做：拖到整理框外面时是**访达**在搬文件，而隐藏标志会跟着文件一起
    /// 搬走 —— 结果就是文件进了目标文件夹却还是隐藏的，在访达里根本看不见。
    /// 所以拖拽一开始就先恢复显示；如果最后落回某个整理框，再重新隐藏。
    static func unhideForDragging(_ itemIDs: [UUID], in boxID: UUID) {
        guard let box = Store.shared.box(id: boxID) else { return }
        for item in box.items where itemIDs.contains(item.id) {
            Store.shared.setPathHidden(false, path: item.path)
        }
    }

    /// 拖拽落回整理框了，把隐藏状态恢复回来（整理框里的条目就该在原位置隐藏）。
    static func rehideAfterDrop(_ itemIDs: [UUID], in boxID: UUID) {
        guard let box = Store.shared.box(id: boxID) else { return }
        for item in box.items where itemIDs.contains(item.id) {
            Store.shared.setItemHidden(true, itemID: item.id, in: boxID)
        }
    }

    static func toggleHidden(_ hidden: Bool, itemID: UUID, in boxID: UUID) {
        Store.shared.setItemHidden(hidden, itemID: itemID, in: boxID)
        BoxWindowManager.shared.refresh(boxID: boxID)
    }
}
