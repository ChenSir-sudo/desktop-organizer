import AppKit

// 命令行辅助模式（不启动界面）
let arguments = CommandLine.arguments
if arguments.contains("--scan") || arguments.contains("--selftest")
    || arguments.contains("--snaptest") || arguments.contains("--hidetest")
    || arguments.contains("--droptest") || arguments.contains("--safetest") {
    Store.shared.persistenceSuppressed = true
}
if arguments.contains("--scan") {
    HeadlessTools.scan()
    exit(0)
}
if arguments.contains("--selftest") {
    HeadlessTools.selfTest()
    exit(0)
}
if arguments.contains("--droptest") {
    HeadlessTools.dropTest()
    exit(0)
}
if arguments.contains("--hidetest") {
    HeadlessTools.hideTest()
    exit(0)
}
if arguments.contains("--snaptest") {
    HeadlessTools.snapTest()
    exit(0)
}

// 单实例：同一个用户只允许跑一个图形实例。
// 两个实例会各自持有一份内存状态，退出时互相覆盖配置 ——
// 那会连 hiddenPaths 一起丢，导致之前隐藏的文件永久隐藏。
if !arguments.contains(where: { $0.hasPrefix("--") }) {
    let lockPath = AppPaths.supportDirectory.appendingPathComponent("instance.lock").path
    let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
    if fd >= 0 {
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            // 已经有一个实例在跑：把它叫到前面，然后自己退出
            if let id = Bundle.main.bundleIdentifier {
                NSRunningApplication.runningApplications(withBundleIdentifier: id)
                    .first?.activate(options: [.activateAllWindows])
            }
            exit(0)
        }
        // 注意：**故意不关闭 fd** —— 进程活着就一直持有这把锁。
    }
}

if arguments.contains("--safetest") {
    let volume = arguments.firstIndex(of: "--safetest").flatMap { index -> String? in
        let next = index + 1
        return next < arguments.count && !arguments[next].hasPrefix("--") ? arguments[next] : nil
    }
    SafetyTests.run(extraVolume: volume)
    exit(0)
}

// 正常启动：主管理窗口 + 若干无边框浮动整理框，视图内容用 SwiftUI 承载。
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
