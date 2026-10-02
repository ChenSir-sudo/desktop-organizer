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
    /// 上报各条目格子的几何与顺序，供 AppKit 层把落点换算成插入下标 / 判断文件夹
    var updateTileFrames: ([UUID: TileGeometry], [UUID]) -> Void = { _, _ in }
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
    /// 进入编辑前的名字，Esc 撤销时用
    @State private var nameBeforeEditing = ""
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
        // 这里刻意不放任何 .onDrop：SwiftUI 只要检测到 onDrop 就会注册一个
        // public.data / public.item 的落点，而 public.file-url 符合 public.data，
        // 于是文件拖拽会被它抢走、根本到不了 AppKit 那层。全部落点统一由
        // BoxContentView 处理。
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
                // 边打字边存。之前只有回车才提交，用户输入完点别处（没按回车）时
                // Store 里还是旧名字，而输入框一直显示新名字、看起来已经改好了，
                // 重启（比如装新版本）就变回旧名字。
                .onChange(of: nameDraft) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.update(id: boxID) { $0.name = trimmed }
                }
                // 失焦也算改完（点别的框 / 切到别的应用 / 点桌面）
                .onChange(of: nameFocused) { _, focused in
                    if !focused && isEditingName { commitName() }
                }
                // 这里刻意不过滤是哪个窗口失焦：多提交一次只是把已经打进 Store 的名字
                // 再收个尾，方向是"更不容易丢名字"。反过来过滤掉才可能漏掉收尾。
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                    if isEditingName { commitName() }
                }
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
                LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
                    ForEach(model.items) { item in
                        ItemTile(
                            item: item,
                            isSelected: ui.selectedItemIDs.contains(item.id),
                            isBeingDragged: session.payload?.itemIDs.contains(item.id) ?? false,
                            isFolderDropTarget: session.folderDropTargetID == item.id,
                            actions: actions
                        )
                        // 拖动源和点选都在 AppKit 侧（BoxContentView）处理 ——
                        // SwiftUI 的 .onDrag 只能带一个文件 URL，多选拖到访达的目录里
                        // 只有第一个文件会被搬走。
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: TileGeometryPreference.self,
                                    value: [item.id: TileGeometry(
                                        id: item.id,
                                        frame: geo.frame(in: .global),
                                        isDirectory: item.isDirectory,
                                        url: item.url
                                    )]
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .padding(.bottom, 4)
                .animation(Motion.items, value: model.items)
                .onPreferenceChange(TileGeometryPreference.self) { geometries in
                    actions.updateTileFrames(geometries, model.items.map(\.id))
                }
                // 点空白处清空选择
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { ui.selectedItemIDs.removeAll() }
                )
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
        nameBeforeEditing = box.name
        nameDraft = box.name
        isEditingName = true
        DispatchQueue.main.async { nameFocused = true }
    }

    /// 结束编辑。名字在打字时就已经存进去了，这里只负责收尾和兜底。
    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空名字不接受，恢复编辑前的
        store.update(id: boxID) { $0.name = trimmed.isEmpty ? nameBeforeEditing : trimmed }
        isEditingName = false
        nameFocused = false
    }

    /// Esc：真的撤销回编辑前的名字（因为打字时已经写进 Store 了）。
    private func cancelName() {
        store.update(id: boxID) { $0.name = nameBeforeEditing }
        nameDraft = nameBeforeEditing
        isEditingName = false
        nameFocused = false
    }
}


// MARK: - 条目格子

struct ItemTile: View {
    let item: ResolvedItem
    let isSelected: Bool
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
            // 用两行占位撑出固定高度，并且让真实名字**顶部对齐**：
            // 这样不管名字一行还是两行，图标位置和名字起点都完全一致。
            ZStack(alignment: .top) {
                Text("占\n位")
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .opacity(0)
                    .accessibilityHidden(true)

                Text(item.name)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .foregroundStyle(item.isBroken ? Color.secondary.opacity(0.6) : (hovering ? Color.primary : Color.secondary))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(
                    isFolderDropTarget ? 0.28 : (isSelected ? 0.20 : (hovering ? 0.10 : 0))
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(isFolderDropTarget ? 0.9 : (isSelected ? 0.75 : 0)),
                    lineWidth: isSelected || isFolderDropTarget ? 2 : 0
                )
        )
        .scaleEffect(isFolderDropTarget ? 1.08 : 1)
        .animation(Motion.folderDrop, value: isFolderDropTarget)
        .animation(Motion.hover, value: isSelected)
        .opacity(isBeingDragged ? 0.35 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }

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


/// 收集各条目格子的几何（SwiftUI 的 .global 是窗口坐标、左上原点）。
struct TileGeometryPreference: PreferenceKey {
    static var defaultValue: [UUID: TileGeometry] = [:]
    static func reduce(value: inout [UUID: TileGeometry], nextValue: () -> [UUID: TileGeometry]) {
        value.merge(nextValue()) { _, new in new }
    }
}
