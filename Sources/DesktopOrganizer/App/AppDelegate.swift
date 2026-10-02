import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let store = Store.shared
    private let windowManager = BoxWindowManager.shared

    private var statusItem: NSStatusItem?
    private var boxListMenu = NSMenu()
    private var mainWindowController: MainWindowController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.load()

        buildMainMenu()
        mainWindowController = MainWindowController()

        store.$boxes
            .receive(on: RunLoop.main)
            .sink { boxes in
                BoxWindowManager.shared.sync(boxes)
            }
            .store(in: &cancellables)

        BoxWindowManager.shared.sync(store.boxes)

        setupStatusItem()
        Diagnostics.runIfRequested()

        if store.prefs.openMainWindowOnLaunch {
            mainWindowController?.show()
        }

        if ProcessInfo.processInfo.environment["DO_DIAG_MAINSETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.mainWindowController?.showSettingsPage()
            }
        }
    }

    // MARK: 主菜单
    //
    // 程序是 .regular（有 Dock 图标），所以必须有一套主菜单，
    // 否则 ⌘Q、⌘V、文本编辑的剪切/拷贝/粘贴全都不可用。
    private func buildMainMenu() {
        let appName = "桌面整理"
        let mainMenu = NSMenu()

        // 应用菜单
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: "0").target = self
        appMenu.addItem(withTitle: "设置…", action: #selector(openMainWindowSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 编辑菜单：文本框的剪切/拷贝/粘贴依赖它
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 窗口菜单
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "显示全部整理框", action: #selector(showAll), keyEquivalent: "").target = self
        windowMenu.addItem(withTitle: "隐藏全部整理框", action: #selector(hideAll), keyEquivalent: "").target = self
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openMainWindowSettings() {
        mainWindowController?.showSettingsPage()
        mainWindowController?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 点 Dock 图标时把主窗口叫回来。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController?.show()
        return true
    }

    // MARK: 菜单栏

    private func setupStatusItem() {
        guard store.prefs.showMenuBarIcon else { return }

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

        menu.addItem(menuItem("打开主窗口", #selector(openMainWindow), key: "0"))
        menu.addItem(.separator())
        menu.addItem(menuItem("新建整理框", #selector(newBox), key: "n"))
        menu.addItem(menuItem("按类型归类桌面（不移动文件）", #selector(categorize), key: "k"))
        menu.addItem(.separator())

        let boxItem = NSMenuItem(title: "整理框", action: nil, keyEquivalent: "")
        boxItem.submenu = boxListMenu
        menu.addItem(boxItem)

        menu.addItem(menuItem("显示全部整理框", #selector(showAll), key: ""))
        menu.addItem(menuItem("隐藏全部整理框", #selector(hideAll), key: ""))
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
                let hidden = windowManager.isHidden(id: box.id)
                let title = "\(box.name)（\(box.items.count) 项）\(hidden ? " · 已隐藏" : "")"
                let item = NSMenuItem(title: title, action: #selector(focusBox(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = box.id
                boxListMenu.addItem(item)
            }
        }
        boxListMenu.addItem(.separator())
        let windowItem = NSMenuItem(title: "打开主窗口…", action: #selector(openMainWindow), keyEquivalent: "")
        windowItem.target = self
        boxListMenu.addItem(windowItem)
    }

    // MARK: 动作

    @objc private func openMainWindow() {
        mainWindowController?.show()
    }

    @objc private func newBox() {
        let box = store.addBox()
        windowManager.sync(store.boxes)
        windowManager.focus(id: box.id)
    }

    @objc private func focusBox(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        windowManager.focus(id: id)
    }

    @objc private func showAll() { windowManager.showAll() }
    @objc private func hideAll() { windowManager.hideAll() }

    @objc private func categorize() {
        mainWindowController?.show()
        let outcome = DeskCategorizer.categorizeIntoBoxes()
        windowManager.sync(store.boxes)
        windowManager.showAll()
        FileActions.info(title: "归类完成", message: outcome.summary)
    }

    @objc private func quit() {
        store.save()
        NSApp.terminate(nil)
    }
}
