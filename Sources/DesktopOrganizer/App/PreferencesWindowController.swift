import AppKit
import SwiftUI

final class PreferencesWindowController {
    private var panel: NSPanel?
    private let store = Store.shared
    private var onOrganize: () -> Void

    init(onOrganize: @escaping () -> Void) {
        self.onOrganize = onOrganize
    }

    func show() {
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let content = PreferencesView(onOrganize: onOrganize)
            .environmentObject(store)

        let hosting = NSHostingView(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "桌面整理 · 设置"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        panel.level = .floating
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
