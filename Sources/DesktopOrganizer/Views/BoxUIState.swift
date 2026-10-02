import SwiftUI

/// 整理框上的两个页面。设置不再向下展开，而是整页切换。
enum BoxPage: Equatable {
    case content
    case settings
}

/// 整理框的界面状态。控制器和视图共享，避免两边各说各话。
final class BoxUIState: ObservableObject {
    @Published var page: BoxPage = .content
    /// 鼠标是否停留在上栏右侧的操作区
    @Published var actionAreaHovered = false
    @Published var isDragging = false
    @Published var isDropTargeted = false
    /// 当前选中的条目。支持点选 / ⌘点选 / ⇧范围选。
    @Published var selectedItemIDs: Set<UUID> = []
    /// 范围选择的锚点
    @Published var selectionAnchor: UUID?
}
