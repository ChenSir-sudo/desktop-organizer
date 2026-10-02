import SwiftUI

/// 整理框的设置**页面**（整页切换，不是向下展开的面板）。
struct BoxSettingsPage: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var ui: BoxUIState

    let boxID: UUID
    let actions: BoxActions

    private var box: BoxConfig { store.box(id: boxID) ?? BoxConfig() }

    private func binding<T>(_ keyPath: WritableKeyPath<BoxConfig, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { store.box(id: boxID)?[keyPath: keyPath] ?? fallback },
            set: { newValue in store.update(id: boxID) { $0[keyPath: keyPath] = newValue } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 11) {
                    nameRow.help("双击上栏标题可以改名")
                    row("背景") { materialPicker }
                    row("透明度") { opacitySlider }
                    row("圆角") { cornerSlider }
                    row("颜色") { colorPicker }
                    floatToggle
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    newBoxButton
                    clearButton
                    deleteButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(Motion.page) {
                    ui.page = .content
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("返回")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text("整理框设置")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: 各行

    private var nameRow: some View {
        HStack(spacing: 8) {
            label("名字")
            Text(box.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private var materialPicker: some View {
        Picker("", selection: binding(\BoxConfig.material, fallback: BoxMaterial.hud)) {
            ForEach(BoxMaterial.allCases) { material in
                Text(material.title).tag(material)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .font(.system(size: 11))
    }

    private var opacitySlider: some View {
        HStack(spacing: 8) {
            Slider(value: binding(\BoxConfig.opacity, fallback: 0.8), in: 0.1...1.0)
                .controlSize(.small)
            Text("\(Int((box.opacity * 100).rounded()))%")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var cornerSlider: some View {
        HStack(spacing: 8) {
            Slider(value: binding(\BoxConfig.cornerRadius, fallback: 20), in: 0...36)
                .controlSize(.small)
            Text("\(Int(box.cornerRadius.rounded()))")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 7) {
            ForEach(AccentPalette.all, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 15, height: 15)
                    .overlay(
                        Circle().strokeBorder(
                            Color.primary.opacity(box.accentHex == hex ? 0.85 : 0),
                            lineWidth: 2
                        )
                    )
                    .contentShape(Circle())
                    .onTapGesture {
                        store.update(id: boxID) { $0.accentHex = hex }
                    }
            }
        }
    }

    private var floatToggle: some View {
        Toggle(isOn: binding(\BoxConfig.floatOnTop, fallback: true)) {
            Text("浮在最上层").font(.system(size: 11.5))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var newBoxButton: some View {
        Button {
            actions.newBox()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("新建整理框").font(.system(size: 11.5))
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
    }

    private var clearButton: some View {
        Button {
            actions.clearItems()
        } label: {
            Text("清空框内条目")
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
        .disabled(store.itemCount(of: boxID) == 0)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            actions.deleteBox()
        } label: {
            Text("删除这个整理框")
                .font(.system(size: 11.5))
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
    }

    // MARK: 布局辅助

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 46, alignment: .leading)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            label(title)
            content()
        }
    }
}
