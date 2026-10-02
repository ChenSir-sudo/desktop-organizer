import AppKit
import SwiftUI

/// 主管理窗口：整理框列表 + 设置。这是「点开之后有操作页面」的那个页面。
final class MainWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let ui = MainUIState()

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil { window = build() }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func showSettingsPage() {
        ui.page = .settings
    }

    private func build() -> NSWindow {
        let root = MainView(
            ui: ui,
            onNewBox: { [weak self] in self?.createBox() },
            onFocusBox: { BoxWindowManager.shared.focus(id: $0) },
            onDeleteBox: { [weak self] in self?.deleteBox($0) },
            onToggleHidden: { [weak self] in self?.toggleHidden($0) },
            onCategorize: { [weak self] in self?.categorize() }
        )
        .environmentObject(Store.shared)

        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "桌面整理"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.minSize = NSSize(width: 620, height: 460)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MainWindow")
        return window
    }

    // MARK: 动作

    private func createBox() {
        let box = Store.shared.addBox()
        BoxWindowManager.shared.sync(Store.shared.boxes)
        BoxWindowManager.shared.focus(id: box.id)
        ui.revision += 1
    }

    private func deleteBox(_ id: UUID) {
        guard let box = Store.shared.box(id: id) else { return }
        let count = box.items.count
        let message = count == 0
            ? "框里没有条目。"
            : "框里的 \(count) 个条目只是引用，磁盘上的文件不会受到任何影响。"
        guard FileActions.confirm(
            title: "删除整理框「\(box.name)」？",
            message: message,
            confirmTitle: "删除整理框"
        ) else { return }
        Store.shared.removeBox(id: id)
        ui.revision += 1
    }

    private func toggleHidden(_ id: UUID) {
        let hidden = BoxWindowManager.shared.isHidden(id: id)
        BoxWindowManager.shared.setHidden(!hidden, id: id)
        ui.revision += 1
    }

    private func categorize() {
        let groups = DeskCategorizer.scanDesktop()
        let total = groups.values.reduce(0) { $0 + $1.count }

        guard total > 0 else {
            FileActions.info(title: "桌面很干净", message: "没有找到需要归类的东西。")
            return
        }

        if Store.shared.prefs.confirmBeforeCategorize {
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
        BoxWindowManager.shared.sync(Store.shared.boxes)
        BoxWindowManager.shared.showAll()
        ui.revision += 1
        FileActions.info(title: "归类完成", message: outcome.summary)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 关掉主窗口不退出程序：Dock 图标和菜单栏还在
    }
}
