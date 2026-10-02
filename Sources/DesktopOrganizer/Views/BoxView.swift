import SwiftUI

/// 整理框对外暴露的动作集合，由 BoxWindowController 注入。
struct BoxActions {
    var dragByMouse: () -> Void = {}
    var endDrag: () -> Void = {}
    var resizeByMouse: () -> Void = {}
    var endResize: () -> Void = {}

    var addFiles: () -> Void = {}
    var deleteBox: () -> Void = {}
    var handleDrop: ([URL]) -> Void = { _ in }

    var chooseFolder: () -> Void = {}
    var revealFolder: () -> Void = {}

    var openItem: (URL) -> Void = { _ in }
    var revealItem: (URL) -> Void = { _ in }
    var moveItemToDesktop: (URL) -> Void = { _ in }
    var moveItemToTrash: (URL) -> Void = { _ in }
}

struct BoxView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: FolderModel
    @ObservedObject var uiState: BoxUIState

    let boxID: UUID
    let actions: BoxActions

    @State private var isTargeted = false
    @State private var isEditingName = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    private var box: BoxConfig { store.box(id: boxID) ?? BoxConfig() }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 8)]
    }

    var body: some View {
        card
            .padding(14)
    }

    // MARK: 卡片

    private var card: some View {
        VStack(spacing: 0) {
            header
            hairline
            content
            if uiState.settingsOpen {
                hairline
                BoxSettingsView(boxID: boxID, actions: actions)
                    .frame(height: 322)
            }
        }
        .background(backgroundLayer)
        .clipShape(RoundedRectangle(cornerRadius: box.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: box.cornerRadius, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color(hex: box.accentHex).opacity(0.95) : Color.primary.opacity(0.13),
                    lineWidth: isTargeted ? 2 : 1
                )
        )
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .shadow(color: .black.opacity(0.30), radius: 16, x: 0, y: 8)
        .dropDestination(for: URL.self) { urls, _ in
            actions.handleDrop(urls)
            return true
        } isTargeted: { targeted in
            if isTargeted != targeted {
                withAnimation(.easeOut(duration: 0.12)) { isTargeted = targeted }
            }
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        ZStack {
            if box.material.isBlurred {
                VisualEffectBackground(material: box.material.nsMaterial, alpha: box.opacity)
            } else {
                Color(nsColor: .windowBackgroundColor).opacity(box.opacity)
            }
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.clear, Color.black.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: box.accentHex))
                .frame(width: 8, height: 8)

            if isEditingName {
                TextField("整理框名字", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onExitCommand { isEditingName = false }
                    .frame(maxWidth: 150)
            } else {
                Text(box.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture(count: 2) { beginEditingName() }
                    .help("双击可以改名")
            }

            Spacer(minLength: 4)

            Text("\(model.totalCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))

            iconButton("plus", help: "添加文件") { actions.addFiles() }
            iconButton("slider.horizontal.3", help: "外观设置") { uiState.settingsOpen.toggle() }
            iconButton("xmark", help: "删除整理框") { actions.deleteBox() }
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

    // MARK: 文件区

    @ViewBuilder
    private var content: some View {
        if let errorText = model.errorText {
            placeholder(symbol: "exclamationmark.triangle", text: errorText)
        } else if model.items.isEmpty {
            placeholder(symbol: "arrow.down.doc", text: "把文件拖到这里")
        } else {
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.items) { item in
                        FileTile(item: item, actions: actions)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

                if model.totalCount > model.items.count {
                    Text("仅显示 \(model.items.count) 项，共 \(model.totalCount) 项")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 12)
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
}

// MARK: - 文件格子

struct FileTile: View {
    let item: FileItem
    let actions: BoxActions

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.10 : 0.0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { actions.openItem(item.url) }
        .contextMenu {
            Button("打开") { actions.openItem(item.url) }
            Button("在访达中显示") { actions.revealItem(item.url) }
            Divider()
            Button("移回桌面") { actions.moveItemToDesktop(item.url) }
            Button("移到废纸篓") { actions.moveItemToTrash(item.url) }
        }
        .help(item.name)
    }
}
