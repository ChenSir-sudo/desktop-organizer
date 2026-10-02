import AppKit

// 命令行辅助模式（不启动界面）
let arguments = CommandLine.arguments
if arguments.contains("--scan") {
    HeadlessTools.scan()
    exit(0)
}
if arguments.contains("--selftest") {
    HeadlessTools.selfTest()
    exit(0)
}

// 正常启动：纯 AppKit 外壳（菜单栏常驻）+ 若干无边框浮动面板。
// 视图内容用 SwiftUI 承载（见 Views/）。
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
