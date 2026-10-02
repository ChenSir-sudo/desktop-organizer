import SwiftUI
import AppKit

/// 整理框对外的动作集合，由 BoxWindowController 注入。
struct BoxActions {
    var dragByMouse: () -> Void = {}
    var endDrag: () -> Void = {}
    var resizeByMouse: () -> Void = {}
    var endResize: () -> Void = {}

    var addFiles: () -> Void = {}
    var deleteBox: () -> Void = {}
    var newBox: () -> Void = {}
    var handleDrop: ([URL]) -> Void = { _ in }

    var openItem: (URL) -> Void = { _ in }
    var revealItem: (URL) -> Void = { _ in }
    var copyItemPath: (URL) -> Void = { _ in }
    var removeItem: (UUID) -> Void = { _ in }
    var trashItem: (URL) -> Void = { _ in }
    var clearItems: () -> Void = {}
    var relocateMissing: () -> Void = {}
}

struct BoxView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: BoxItemsModel
    @ObservedObject var ui: BoxUIState

    let boxID: UUID
    let actions: BoxActions

    @State private var isEditingName = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    private var box: BoxConfig { store.box(id: boxID) ?? BoxConfig() }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: box.cornerRadius, style: .continuous)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 8)]
    }

    var body: some View {
        card.padding(14)
    }

    // MARK: 卡片外壳

    private var card: some View {
        ZStack {
            background
            pages
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                ui.isDropTargeted
                    ? Color(hex: box.accentHex).opacity(0.95)
                    : Color.white.opacity(0.14),
                lineWidth: ui.isDropTargeted ? 2 : 1
            )
        )
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 7)
        .animation(.easeOut(duration: 0.15), value: ui.isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            actions.handleDrop(urls)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.14)) { ui.isDropTargeted = targeted }
        }
    }

    /// 只有毛玻璃/纯色一层，没有额外的浅色叠加层。
    @ViewBuilder
    private var background: some View {
        if box.material.isBlurred {
            VisualEffectBackground(
                material: box.material.nsMaterial,
                alpha: box.opacity,
                cornerRadius: box.cornerRadius
            )
        } else {
            Color(nsColor: .underPageBackgroundColor).opacity(box.opacity)
        }
    }

    // MARK: 页面切换

    private var pages: some View {
        ZStack {
            if ui.page == .content {
                contentPage
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                BoxSettingsPage(ui: ui, boxID: boxID, actions: actions)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: ui.page)
    }

    private var contentPage: some View {
        VStack(spacing: 0) {
            header
            hairline
            content
        }
    }

    private var hairline: some View {
        Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
    }

    // MARK: 上栏

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: box.accentHex)).frame(width: 8, height: 8)

            titleView

            Spacer(minLength: 4)

            Text("\(model.items.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .opacity(ui.actionAreaHovered ? 0 : 1)

            actionArea
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in actions.dragByMouse() }
                .onEnded { _ in actions.endDrag() }
        )
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingName {
            TextField("整理框名字", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .focused($nameFocused)
                .onSubmit(commitName)
                .onExitCommand { cancelName() }
                .frame(maxWidth: 150)
        } else {
            Text(box.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
                // 只有双击标题才能改名，避免拖动或单击误触
                .onTapGesture(count: 2) { beginEditingName() }
                .help("双击改名")
        }
    }

    /// 右上角操作区：平时隐藏，鼠标移到上栏右侧才出现。
    private var actionArea: some View {
        HStack(spacing: 2) {
            iconButton("plus", help: "添加文件（只做引用，不移动）") { actions.addFiles() }
            iconButton("slider.horizontal.3", help: "设置") {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    ui.page = .settings
                }
            }
            iconButton("xmark", help: "删除整理框") { actions.deleteBox() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.primary.opacity(ui.actionAreaHovered ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .opacity(ui.actionAreaHovered ? 1 : 0)
        .scaleEffect(ui.actionAreaHovered ? 1 : 0.92, anchor: .trailing)
        .animation(.easeOut(duration: 0.18), value: ui.actionAreaHovered)
        .onHover { hovering in
            ui.actionAreaHovered = hovering
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }

    // MARK: 文件网格

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.items) { item in
                        ItemTile(
                            item: item,
                            highlighted: ui.highlightedItemIDs.contains(item.id),
                            actions: actions
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.items)

                Text("共 \(model.items.count) 项 · 文件都在原位置，这里只是引用")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .light))
            Text("把文件拖到这里")
                .font(.system(size: 12, weight: .medium))
            Text("只做归类，不会移动文件")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: 右下角缩放

    private var resizeGrip: some View {
        ZStack {
            Color.clear
            Path { path in
                path.move(to: CGPoint(x: 15, y: 5))
                path.addLine(to: CGPoint(x: 5, y: 15))
                path.move(to: CGPoint(x: 15, y: 10))
                path.addLine(to: CGPoint(x: 10, y: 15))
            }
            .stroke(Color.primary.opacity(0.28), lineWidth: 1.4)
        }
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
        .padding(6)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in actions.resizeByMouse() }
                .onEnded { _ in actions.endResize() }
        )
        .help("拖动调整大小")
    }

    // MARK: 改名

    private func beginEditingName() {
        nameDraft = box.name
        isEditingName = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.update(id: boxID) { $0.name = trimmed }
        }
        isEditingName = false
        nameFocused = false
    }

    private func cancelName() {
        isEditingName = false
        nameFocused = false
    }
}

// MARK: - 条目格子

struct ItemTile: View {
    let item: ResolvedItem
    let highlighted: Bool
    let actions: BoxActions

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)
                    .opacity(item.isBroken ? 0.35 : 1)

                if item.isBroken {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(Circle().fill(Color.orange))
                        .offset(x: 4, y: -3)
                }
            }
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .foregroundStyle(item.isBroken ? Color.secondary.opacity(0.6) : (hovering ? Color.primary : Color.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(highlighted ? 0.16 : (hovering ? 0.10 : 0)))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            if item.exists { actions.openItem(item.url) }
        }
        .contextMenu {
            if item.exists {
                Button("打开") { actions.openItem(item.url) }
                Button("在访达中显示") { actions.revealItem(item.url) }
            } else {
                Text("文件已不在原位置")
            }
            Divider()
            Button("复制路径") { actions.copyItemPath(item.url) }
            Button("从框中移除") { actions.removeItem(item.id) }
            if item.exists {
                Divider()
                Button("移到废纸篓…") { actions.trashItem(item.url) }
            }
        }
        .help(item.isBroken ? "\(item.name)\n（文件已不在原位置）" : item.url.path)
    }
}
