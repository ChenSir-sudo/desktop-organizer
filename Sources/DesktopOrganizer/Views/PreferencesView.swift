import SwiftUI
import AppKit

struct PreferencesView: View {
    @EnvironmentObject private var store: Store
    var onOrganize: () -> Void

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { store.prefs[keyPath: keyPath] },
            set: { store.prefs[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("归档位置")
                    .font(.system(size: 12, weight: .semibold))
                Text("被整理的文件会移动到这里，按整理框名字分子文件夹。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(store.prefs.rootURL.path)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )
                    Button("选择…") { chooseRoot() }
                        .controlSize(.small)
                    Button("打开") { NSWorkspace.shared.open(store.prefs.rootURL) }
                        .controlSize(.small)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("新建整理框的默认外观")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    Text("背景").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                    Picker("", selection: binding(\.defaultMaterial)) {
                        ForEach(BoxMaterial.allCases) { material in
                            Text(material.title).tag(material)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Text("透明度").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                    Slider(value: binding(\.defaultOpacity), in: 0.15...1.0).controlSize(.small)
                    Text("\(Int((store.prefs.defaultOpacity * 100).rounded()))%")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text("圆角").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                    Slider(value: binding(\.defaultCornerRadius), in: 0...36).controlSize(.small)
                    Text("\(Int(store.prefs.defaultCornerRadius.rounded()))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                Toggle(isOn: binding(\.defaultFloatOnTop)) {
                    Text("新框默认窗口置顶").font(.system(size: 11.5))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: binding(\.confirmBeforeOrganize)) {
                    Text("一键分类前先确认").font(.system(size: 11.5))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Button {
                    onOrganize()
                } label: {
                    Text("立即一键分类整理桌面").frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            }

            Text("提示：整理框只搬运文件，不会删除任何东西。如果读不到桌面，请在「系统设置 › 隐私与安全性 › 文件与文件夹」里允许本程序访问桌面。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 430, alignment: .topLeading)
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.directoryURL = store.prefs.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            store.prefs.rootPath = url.path
            store.save()
        }
    }
}
