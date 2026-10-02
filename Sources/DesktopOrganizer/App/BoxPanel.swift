import AppKit
import SwiftUI

/// 无边框、可浮动的整理框面板。
final class BoxPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
