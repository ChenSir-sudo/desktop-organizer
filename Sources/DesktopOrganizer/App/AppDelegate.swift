import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let store = Store.shared
    private let windowManager = BoxWindowManager.shared

    private var statusItem: NSStatusItem?
    private var boxListMenu = NSMenu()
    private var preferencesController: PreferencesWindowController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()

        store.$boxes
            .receive(on: RunLoop.main)
            .sink { boxes in
                BoxWindowManager.shared.sync(boxes)
            }
            .store(in: &cancellables)

        BoxWindowManager.shared.sync(store.boxes)

        setupStatusItem()
        preferencesController = PreferencesWindowController(onOrganize: { [weak self] in
            self?.runOrganize()
        })

        Diagnostics.runIfRequested()

        if ProcessInfo.processInfo.environment["DO_DIAG_PREFS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.openPreferences() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "桌面整理")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "桌面整理"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(menuItem("新建整理框", #selector(newBox), key: "n"))
        menu.addItem(menuItem("一键分类整理桌面", #selector(organize), key: "k"))

        menu.addItem(.separator())

        let boxItem = NSMenuItem(title: "整理框", action: nil, keyEquivalent: "")
        boxItem.submenu = boxListMenu
        menu.addItem(boxItem)

        menu.addItem(menuItem("显示全部整理框", #selector(showAll), key: ""))
        menu.addItem(menuItem("隐藏全部整理框", #selector(hideAll), key: ""))

        menu.addItem(.separator())

        menu.addItem(menuItem("打开归档文件夹", #selector(openRootFolder), key: ""))
        menu.addItem(menuItem("设置…", #selector(openPreferences), key: ","))

        menu.addItem(.separator())

        menu.addItem(menuItem("退出桌面整理", #selector(quit), key: "q"))

        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = true
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }

        boxListMenu.removeAllItems()
        let boxes = store.boxes
        if boxes.isEmpty {
            let empty = NSMenuItem(title: "还没有整理框", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            boxListMenu.addItem(empty)
        } else {
            for box in boxes {
                let item = NSMenuItem(title: "\(box.name)（\(box.folderURL.lastPathComponent)）", action: #selector(focusBox(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = box.id
                boxListMenu.addItem(item)
            }
        }
        boxListMenu.addItem(.separator())
        let removeItem = NSMenuItem(title: "整理框管理…", action: #selector(openPreferences), keyEquivalent: "")
        removeItem.target = self
        boxListMenu.addItem(removeItem)
    }

    // MARK: 动作

    @objc private func newBox() {
        let name = "整理框 \(store.boxes.count + 1)"
        let box = store.addBox(name: name, folder: nil)
        BoxWindowManager.shared.focus(id: box.id)
    }

    @objc private func focusBox(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        BoxWindowManager.shared.focus(id: id)
    }

    @objc private func showAll() {
        BoxWindowManager.shared.showAll()
    }

    @objc private func hideAll() {
        BoxWindowManager.shared.hideAll()
    }

    @objc private func openRootFolder() {
        let url = store.prefs.rootURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func openPreferences() {
        preferencesController?.show()
    }

    @objc private func organize() {
        runOrganize()
    }

    @objc private func quit() {
        store.save()
        NSApp.terminate(nil)
    }

    // MARK: 一键分类

    private func runOrganize() {
        let groups = DeskSorter.scanDesktop()
        let total = groups.values.reduce(0) { $0 + $1.count }

        guard total > 0 else {
            presentInfo(title: "桌面很干净", message: "没有找到需要整理的文件。")
            return
        }

        if store.prefs.confirmBeforeOrganize {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "把桌面上的 \(total) 个文件按类型整理？"
            let detail = FileCategory.allCases
                .compactMap { category -> String? in
                    guard let urls = groups[category], !urls.isEmpty else { return nil }
                    return "\(category.rawValue)  \(urls.count) 项"
                }
                .joined(separator: "\n")
            alert.informativeText = detail + "\n\n移动目标：\n\(store.prefs.rootURL.path)"
            alert.addButton(withTitle: "开始整理")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let (_, summary) = DeskSorter.organize()
        BoxWindowManager.shared.sync(store.boxes)
        BoxWindowManager.shared.showAll()
        BoxWindowManager.shared.refreshAll()
        presentInfo(title: "整理完成", message: summary)
    }

    private func presentInfo(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
