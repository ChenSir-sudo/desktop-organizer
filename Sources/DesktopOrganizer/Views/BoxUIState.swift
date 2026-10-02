import SwiftUI

/// 整理框的界面状态。放在控制器里，让「展开设置面板」既可以被界面上的按钮触发，
/// 也可以被菜单等外部逻辑触发，两边不会各说各话。
final class BoxUIState: ObservableObject {
    @Published var settingsOpen: Bool = false
}
