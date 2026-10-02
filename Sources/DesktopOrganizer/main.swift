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
if arguments.contains("--snaptest") {
    HeadlessTools.snapTest()
    exit(0)
}

// 正常启动：主管理窗口 + 若干无边框浮动整理框，视图内容用 SwiftUI 承载。
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
