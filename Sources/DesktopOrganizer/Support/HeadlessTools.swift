import AppKit

/// 无界面自检工具，用于在命令行里验证分类规则和搬移逻辑：
///   桌面整理.app/Contents/MacOS/DesktopOrganizer --scan      只看分类结果，不动文件
///   桌面整理.app/Contents/MacOS/DesktopOrganizer --selftest  在临时目录里跑一遍完整搬移
enum HeadlessTools {

    static func scan() {
        Store.shared.load()
        let groups = DeskSorter.scanDesktop()
        let total = groups.values.reduce(0) { $0 + $1.count }

        print("归档根目录: \(Store.shared.prefs.rootURL.path)")
        print("桌面待整理: \(total) 项")
        print("")
        if total == 0 {
            print("（没有需要整理的文件）")
            return
        }
        for category in FileCategory.allCases {
            guard let urls = groups[category], !urls.isEmpty else { continue }
            print("\(category.rawValue)（\(urls.count)）")
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                print("    \(url.lastPathComponent)")
            }
        }
    }

    static func selfTest() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(".cache/selftest", isDirectory: true)
        try? fm.removeItem(at: root)

        let source = root.appendingPathComponent("src", isDirectory: true)
        let target = root.appendingPathComponent("dst", isDirectory: true)
        try? fm.createDirectory(at: source, withIntermediateDirectories: true)
        try? fm.createDirectory(at: source.appendingPathComponent("一个文件夹"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: source.appendingPathComponent("Demo.app"), withIntermediateDirectories: true)

        let samples = [
            "照片.png", "截图.JPG", "报告.pdf", "笔记.md", "表格.xlsx",
            "视频.mp4", "音乐.mp3", "压缩包.zip", "安装包.dmg",
            "脚本.py", "未知文件.zzz", "没有扩展名"
        ]
        for name in samples {
            try? "hello".write(to: source.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        guard let urls = try? fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            print("自检失败：无法列出测试目录")
            return
        }

        print("== 分类结果 ==")
        var seen: [FileCategory: Int] = [:]
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let category = DeskSorter.category(for: url)
            seen[category, default: 0] += 1
            print("  \(url.lastPathComponent)  ->  \(category.rawValue)")
        }

        print("")
        print("== 第一次搬移 ==")
        let first = FileMover.move(urls, into: target)
        print("  成功 \(first.moved.count) / 跳过 \(first.skipped.count) / 失败 \(first.failures.count)")
        for failure in first.failures {
            print("  失败: \(failure.url.lastPathComponent) - \(failure.reason)")
        }

        print("")
        print("== 重复移动（应全部跳过）==")
        let again = FileMover.move(first.moved, into: target)
        print("  成功 \(again.moved.count) / 跳过 \(again.skipped.count) / 失败 \(again.failures.count)")

        print("")
        print("== 同名冲突处理 ==")
        let conflict = source.appendingPathComponent("照片.png")
        try? "second".write(to: conflict, atomically: true, encoding: .utf8)
        let conflictResult = FileMover.move([conflict], into: target)
        print("  结果: \(conflictResult.moved.map { $0.lastPathComponent })")

        print("")
        print("== 目标文件夹内容 ==")
        let names = (try? fm.contentsOfDirectory(atPath: target.path))?.sorted() ?? []
        for name in names { print("  \(name)") }

        print("")
        print("== 保护规则 ==")
        let selfProtected = FileMover.move([Bundle.main.bundleURL], into: target)
        print("  尝试搬移程序自身 -> 失败 \(selfProtected.failures.count)（应为 1）")

        // 清理
        try? fm.removeItem(at: root)
        print("")
        print("自检结束")
    }
}
