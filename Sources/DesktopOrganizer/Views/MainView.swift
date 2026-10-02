import SwiftUI

enum MainPage: Equatable {
    case boxes
    case settings
}

final class MainUIState: ObservableObject {
    @Published var page: MainPage = .boxes
    @Published var hoveredBoxID: UUID?
    /// 外部状态（比如显示/隐藏）变化时，用它强制刷新卡片
    @Published var revision: Int = 0
}

struct MainView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var ui: MainUIState

    var onNewBox: () -> Void = {}
    var onFocusBox: (UUID) -> Void = { _ in }
    var onDeleteBox: (UUID) -> Void = { _ in }
    var onToggleHidden: (UUID) -> Void = { _ in }
    var onCategorize: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.5)
            ZStack {
                if ui.page == .boxes {
                    boxesPage
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else {
                    SettingsPage(onCategorize: onCategorize, onNewBox: onNewBox)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: ui.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("桌面整理")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(store.boxes.count) 个整理框")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            pageSwitch

            Button(action: onNewBox) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("新建").font(.system(size: 12, weight: .medium))
                }
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var pageSwitch: some View {
        HStack(spacing: 2) {
            segment("整理框", page: .boxes)
            segment("设置", page: .settings)
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func segment(_ title: String, page: MainPage) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { ui.page = page }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(ui.page == page ? Color(nsColor: .controlBackgroundColor) : .clear)
                )
                .foregroundStyle(ui.page == page ? Color.primary : Color.secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 整理框页

    private var boxesPage: some View {
        ScrollView(.vertical) {
            if store.boxes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("还没有整理框")
                        .font(.system(size: 13, weight: .medium))
                    Button("新建整理框", action: onNewBox)
                        .controlSize(.regular)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 90)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(store.boxes) { box in
                        BoxCard(
                            box: box,
                            hidden: BoxWindowManager.shared.isHidden(id: box.id),
                            hovered: ui.hoveredBoxID == box.id,
                            onFocus: { onFocusBox(box.id) },
                            onDelete: { onDeleteBox(box.id) },
                            onToggleHidden: { onToggleHidden(box.id) }
                        )
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.15)) {
                                ui.hoveredBoxID = hovering ? box.id : (ui.hoveredBoxID == box.id ? nil : ui.hoveredBoxID)
                            }
                        }
                    }
                }
                .padding(18)
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: store.boxes)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 整理框卡片

private struct BoxCard: View {
    let box: BoxConfig
    let hidden: Bool
    let hovered: Bool
    let onFocus: () -> Void
    let onDelete: () -> Void
    let onToggleHidden: () -> Void

    private var brokenCount: Int {
        box.items.filter { !$0.exists }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: box.accentHex))
                    .frame(width: 9, height: 9)
                Text(box.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if hidden {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 6) {
                Text("\(box.items.count) 项")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if brokenCount > 0 {
                    Text("· \(brokenCount) 个已失效")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 6) {
                smallButton(hidden ? "显示" : "隐藏", symbol: hidden ? "eye" : "eye.slash", action: onToggleHidden)
                smallButton("定位", symbol: "scope", action: onFocus)
                Spacer(minLength: 0)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除整理框（不会影响文件）")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovered ? 0.16 : 0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(count: 2, perform: onFocus)
        .help("双击定位到这个整理框")
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
                Text(title).font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
