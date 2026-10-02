import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 整理框对外的动作集合，由 BoxWindowController 注入。
struct BoxActions {
    var dragByMouse: () -> Void = {}
    var endDrag: () -> Void = {}
    var resizeByMouse: () -> Void = {}
    var endResize: () -> Void = {}

    var addFiles: () -> Void = {}
    var deleteBox: () -> Void = {}
    var newBox: () -> Void = {}
    /// 外部文件拖入
    var handleDrop: ([URL]) -> Void = { _ in }

    var openItem: (URL) -> Void = { _ in }
    var revealItem: (URL) -> Void = { _ in }
    var copyItemPath: (URL) -> Void = { _ in }
    var openInEditor: (URL) -> Void = { _ in }
    /// 菜单上显示的编辑器名字，没装编辑器时为空
    var editorName: String = ""
    var openInTerminal: (URL) -> Void = { _ in }
    var removeItem: (UUID) -> Void = { _ in }
    var trashItem: (URL) -> Void = { _ in }
    var toggleItemHidden: (UUID, Bool) -> Void = { _, _ in }
    var clearItems: () -> Void = {}
}

struct BoxView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: BoxItemsModel
    @ObservedObject var ui: BoxUIState
    @ObservedObject private var session = DragSession.shared

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
        .onDrop(of: Self.dropTypes, isTargeted: dropTargetBinding) { providers in
            handleProviders(providers)
        }
    }

    /// 只注册内部拖拽用的自定义类型。外部文件（public.file-url）由
    /// BoxContentView 在 AppKit 层接收 —— SwiftUI 那条链路在 LazyVGrid /
    /// ScrollView / 卡片之间路由不稳定，实测「拖到格子上能进、拖到空白处进不去」。
    static let dropTypes: [UTType] = [DragPayload.utType]

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { ui.isDropTargeted },
            set: { targeted in withAnimation(Motion.dropTarget) { ui.isDropTargeted = targeted } }
        )
    }

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

    // MARK: 落点处理

    /// 卡片空白处的落点：处理「从别的框拖过来的条目」和「外部文件」。
    /// 框内重排由每个格子的 DropDelegate 处理，不会走到这里。
    private func handleProviders(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(DragPayload.typeIdentifier) {
                DragPayload.payload(from: provider) { payload in
                    guard payload.boxID != boxID else { return }
                    DragSession.shared.handled = true
                    Commands.transfer(itemID: payload.itemID, from: payload.boxID, to: boxID, at: model.items.count)
                    DragSession.shared.finish()
                }
                handled = true
            }
        }
        return handled
    }

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
        .animation(Motion.page, value: ui.page)
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

            // 数量气泡和右上角按钮是同一组：共用一个悬停区域，
            // 否则鼠标从左边的气泡滑过去时悬停会断掉，两边一起闪烁。
            HStack(spacing: 6) {
                countBubble
                actionArea
            }
            .contentShape(Rectangle())
            .onHover { hovering in ui.actionAreaHovered = hovering }
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
                .onTapGesture(count: 2) { beginEditingName() }
                .help("双击改名")
        }
    }

    /// 右上角操作区：平时隐藏，鼠标移到上栏右侧才出现。
    private var actionArea: some View {
        HStack(spacing: 2) {
            iconButton("plus", help: "添加文件") { actions.addFiles() }
            iconButton("slider.horizontal.3", help: "设置") {
                withAnimation(Motion.page) {
                    ui.page = .settings
                }
            }
            iconButton("xmark", help: "删除整理框") { actions.deleteBox() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(ui.actionAreaHovered ? 0.06 : 0)))
        .contentShape(Rectangle())
        .opacity(ui.actionAreaHovered ? 1 : 0)
        .scaleEffect(ui.actionAreaHovered ? 1 : 0.92, anchor: .trailing)
        .animation(Motion.hover, value: ui.actionAreaHovered)
    }

    /// 文件数量气泡。跟右上角按钮一起显隐，锚点在右侧，像是从按钮那边长出来的。
    private var countBubble: some View {
        Text("\(model.items.count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .opacity(ui.actionAreaHovered ? 1 : 0)
            .scaleEffect(ui.actionAreaHovered ? 1 : 0.92, anchor: .trailing)
            .animation(Motion.hover, value: ui.actionAreaHovered)
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
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        ItemTile(
                            item: item,
                            isBeingDragged: session.payload?.itemID == item.id,
                            isFolderDropTarget: session.folderDropTargetID == item.id,
                            actions: actions
                        )
                        .onDrag {
                            let payload = DragPayload(boxID: boxID, itemID: item.id)
                            session.begin(payload)
                            return DragPayload.provider(for: payload)
                        } preview: {
                            dragPreview(for: item)
                        }
                        .onDrop(
                            of: [DragPayload.utType],
                            delegate: ItemDropDelegate(
                                targetIndex: index,
                                boxID: boxID,
                                targetItem: item,
                                model: model,
                                session: session
                            )
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .padding(.bottom, 4)
                .animation(Motion.items, value: model.items)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 有内容时 ScrollView 铺满整块，空白处的落点会被它吃掉
            .onDrop(of: Self.dropTypes, isTargeted: dropTargetBinding) { providers in
                handleProviders(providers)
            }
        }
    }

    private func dragPreview(for item: ResolvedItem) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: item.icon).resizable().frame(width: 20, height: 20)
            Text(item.name).font(.system(size: 11)).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .light))
            Text("把文件拖到这里")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
        .onDrop(of: Self.dropTypes, isTargeted: dropTargetBinding) { providers in
            handleProviders(providers)
        }
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

// MARK: - 框内重排 / 跨框转移

struct ItemDropDelegate: DropDelegate {
    let targetIndex: Int
    let boxID: UUID
    let targetItem: ResolvedItem
    @ObservedObject var model: BoxItemsModel
    @ObservedObject var session: DragSession

    /// 必须同时接受外部文件 URL。只认自定义类型的话，格子一多就会铺满整个框，
    /// 从访达拖进来的文件落在格子上会被拒绝，表现成「文件一多就拖不进去」。
    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [DragPayload.utType])
    }

    func dropEntered(info: DropInfo) {
        if let payload = session.payload, payload.boxID == boxID {
            session.handled = true
            Store.shared.moveItem(in: boxID, itemID: payload.itemID, to: targetIndex)
            model.refresh(force: true)
            return
        }
        // 外部文件悬停在文件夹图标上：高亮，提示「会放进这个文件夹」
        if targetItem.exists, targetItem.isDirectory {
            session.folderDropTargetID = targetItem.id
        }
    }

    func dropExited(info: DropInfo) {
        if session.folderDropTargetID == targetItem.id {
            session.folderDropTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        // 内部拖拽：重排 / 跨框转移
        if let payload = session.payload {
            session.handled = true
            if payload.boxID == boxID {
                Commands.reorder(in: boxID, itemID: payload.itemID, to: targetIndex)
            } else {
                Commands.transfer(itemID: payload.itemID, from: payload.boxID, to: boxID, at: targetIndex)
            }
            DispatchQueue.main.async { session.finish() }
            return true
        }

        return false
    }
}

// MARK: - 条目格子

struct ItemTile: View {
    let item: ResolvedItem
    let isBeingDragged: Bool
    let isFolderDropTarget: Bool
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
                    badge("exclamationmark.triangle.fill", color: .orange)
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
                .fill(Color.accentColor.opacity(isFolderDropTarget ? 0.28 : (hovering ? 0.10 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(isFolderDropTarget ? 0.9 : 0), lineWidth: 2)
        )
        .scaleEffect(isFolderDropTarget ? 1.08 : 1)
        .animation(Motion.folderDrop, value: isFolderDropTarget)
        .opacity(isBeingDragged ? 0.35 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            if item.exists { actions.openItem(item.url) }
        }
        .contextMenu { menu }
        .help(item.isBroken ? "\(item.name)\n（文件已不在原位置）" : item.url.path)
    }

    private func badge(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8))
            .foregroundStyle(.white)
            .padding(2.5)
            .background(Circle().fill(color))
            .offset(x: 4, y: -3)
    }

    @ViewBuilder
    private var menu: some View {
        if item.exists {
            Button("打开") { actions.openItem(item.url) }
            if !actions.editorName.isEmpty {
                Button("用 \(actions.editorName) 打开") { actions.openInEditor(item.url) }
            }
            Button("在终端中打开") { actions.openInTerminal(item.url) }
            Button("在访达中显示") { actions.revealItem(item.url) }
            Divider()
            if HiddenFlag.isHidden(item.url) {
                Button("显示原文件") { actions.toggleItemHidden(item.id, false) }
            } else {
                Button("隐藏原文件") { actions.toggleItemHidden(item.id, true) }
            }
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
}
