import SwiftUI
import AppKit

/// 主窗口里的设置页（需求：在设置页面里也能新建整理框）。
struct SettingsPage: View {
    @EnvironmentObject private var store: Store

    var onCategorize: () -> Void = {}
    var onNewBox: () -> Void = {}

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { store.prefs[keyPath: keyPath] },
            set: { store.prefs[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                section("新建整理框") {
                    Text("整理框只是「引用集合」，文件永远留在原来的位置。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button(action: onNewBox) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            Text("新建整理框").font(.system(size: 12, weight: .medium))
                        }
                    }
                    .controlSize(.regular)
                }

                Divider()

                section("新整理框的默认外观") {
                    row("背景") {
                        Picker("", selection: binding(\.defaultMaterial)) {
                            ForEach(BoxMaterial.allCases) { material in
                                Text(material.title).tag(material)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: 220)
                    }
                    row("透明度") {
                        Slider(value: binding(\.defaultOpacity), in: 0.1...1.0)
                            .controlSize(.small)
                            .frame(maxWidth: 220)
                        Text("\(Int((store.prefs.defaultOpacity * 100).rounded()))%")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    row("圆角") {
                        Slider(value: binding(\.defaultCornerRadius), in: 0...36)
                            .controlSize(.small)
                            .frame(maxWidth: 220)
                        Text("\(Int(store.prefs.defaultCornerRadius.rounded()))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Toggle(isOn: binding(\.defaultFloatOnTop)) {
                        Text("新整理框默认窗口置顶").font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                Divider()

                section("桌面归类") {
                    Text("扫描桌面并按类型建立整理框。文件不会被移动，只是被引用。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Toggle(isOn: binding(\.confirmBeforeCategorize)) {
                        Text("执行前先确认").font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Button(action: onCategorize) {
                        Text("按类型归类桌面").font(.system(size: 12, weight: .medium))
                    }
                    .controlSize(.regular)
                }

                Divider()

                section("启动") {
                    Toggle(isOn: binding(\.openMainWindowOnLaunch)) {
                        Text("启动时打开这个窗口").font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    Toggle(isOn: binding(\.showMenuBarIcon)) {
                        Text("在菜单栏显示图标").font(.system(size: 11.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                Divider()

                section("关于") {
                    Text("整理框只记录文件位置，不会移动、改名或删除你的文件。整个程序里唯一会动文件的地方是条目右键菜单里的「移到废纸篓」，且每次都会二次确认。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("如果整理框显示「已失效」，说明那个文件被移动或删除了 —— 引用不会自动跟踪，右键移除即可。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}
