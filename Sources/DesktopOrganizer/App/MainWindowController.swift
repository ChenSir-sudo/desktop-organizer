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
            onCategorize: { [weak self] in self?.categorize() },
            onTidyBox: { [weak self] in self?.tidyBox($0) }
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
        Commands.createBox()
        ui.revision += 1
    }

    private func deleteBox(_ id: UUID) {
        guard Commands.confirmAndDeleteBox(id) else { return }
        ui.revision += 1
    }

    private func toggleHidden(_ id: UUID) {
        BoxWindowManager.shared.setHidden(!BoxWindowManager.shared.isHidden(id: id), id: id)
        ui.revision += 1
    }

    private func tidyBox(_ id: UUID) {
        let placed = BoxWindowManager.shared.tidy(boxID: id)
        if placed == 0 {
            FileActions.info(title: "这个框里没有图标",
                             message: "把桌面图标拖进框的范围里，再点整理。")
        }
        ui.revision += 1
    }

    private func categorize() {
        Commands.categorizeDesktop()
        ui.revision += 1
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // 关掉主窗口不退出程序：Dock 图标和菜单栏还在
    }
}
