import SwiftUI

struct BoxSettingsView: View {
    @EnvironmentObject private var store: Store
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
        VStack(alignment: .leading, spacing: 10) {
            row("名字") {
                TextField("整理框名字", text: binding(\BoxConfig.name, fallback: ""))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(roundedField)
            }

            row("文件夹") {
                HStack(spacing: 6) {
                    Text(box.folderURL.path)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    smallButton("选择…") { actions.chooseFolder() }
                    smallButton("显示") { actions.revealFolder() }
                }
            }

            row("背景") {
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

            row("透明度") {
                HStack(spacing: 8) {
                    Slider(value: binding(\BoxConfig.opacity, fallback: 0.88), in: 0.15...1.0)
                        .controlSize(.small)
                    Text("\(Int((box.opacity * 100).rounded()))%")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }

            row("圆角") {
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

            row("颜色") {
                HStack(spacing: 7) {
                    ForEach(AccentPalette.all, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle().strokeBorder(
                                    Color.primary.opacity(box.accentHex == hex ? 0.85 : 0.0),
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

            Toggle(isOn: binding(\BoxConfig.floatOnTop, fallback: true)) {
                Text("窗口置顶")
                    .font(.system(size: 11.5))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                actions.deleteBox()
            } label: {
                Text("删除这个整理框")
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
    }

    private var roundedField: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.08))
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            content()
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5))
        }
        .controlSize(.mini)
        .buttonStyle(.bordered)
    }
}
