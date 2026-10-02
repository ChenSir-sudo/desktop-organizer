import AppKit

/// 无界面自检：
///   --scan      只看桌面会被怎么归类，不写任何东西
///   --selftest  在临时目录里验证「引用模式」不会移动文件
///   --snaptest  验证窗口吸附与引导线的几何计算
enum HeadlessTools {

    /// 吸附逻辑必须可预测：靠近另一窗口的边/中线时吸住，并给出对应引导线。
    static func snapTest() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 918)
        let other = CGRect(x: 500, y: 400, width: 300, height: 360)   // 500..800 / 400..760
        var failures = 0

        func check(_ name: String, _ actual: CGFloat, _ expected: CGFloat) {
            let ok = abs(actual - expected) < 0.01
            if !ok { failures += 1 }
            print("  \(ok ? "OK " : "!! ") \(name): \(actual)  期望 \(expected)")
        }

        func describe(_ guides: [GuideLine]) -> String {
            guides.isEmpty ? "无"
                : guides.map { $0.axis == .vertical ? "竖线@\(Int($0.position))" : "横线@\(Int($0.position))" }
                    .joined(separator: " + ")
        }

        print("== 左边缘与另一框左边缘对齐（差 3pt）==")
        let a = SnapEngine.snap(
            moving: CGRect(x: 503, y: 100, width: 200, height: 100),
            others: [other], screen: screen
        )
        check("吸附后 minX", a.origin.x, 500)
        print("  引导线: \(describe(a.guides))")

        print("== 贴边拼接：本框左边缘吸到另一框右边缘（差 4pt）==")
        let b = SnapEngine.snap(
            moving: CGRect(x: 796, y: 100, width: 200, height: 100),
            others: [other], screen: screen
        )
        check("吸附后 minX", b.origin.x, 800)

        print("== 贴边拼接：本框下边缘吸到另一框上边缘（差 5pt）==")
        let c = SnapEngine.snap(
            moving: CGRect(x: 100, y: 755, width: 200, height: 100),
            others: [other], screen: screen
        )
        check("吸附后 minY", c.origin.y, 760)

        print("== 超出 8pt 阈值：不吸附、不画引导线 ==")
        let far = SnapEngine.snap(
            moving: CGRect(x: 600, y: 200, width: 200, height: 100),
            others: [], screen: screen
        )
        check("保持原位 x", far.origin.x, 600)
        check("保持原位 y", far.origin.y, 200)
        if !far.guides.isEmpty {
            failures += 1
            print("  !! 不该有引导线，实际: \(describe(far.guides))")
        } else {
            print("  OK  没有引导线")
        }

        print("== 屏幕中线吸附 ==")
        let e = SnapEngine.snap(
            moving: CGRect(x: 585, y: 100, width: 300, height: 100),
            others: [], screen: screen
        )
        check("frame.midX", e.origin.x + 150, 735)

        print("")
        print(failures == 0 ? "吸附自检全部通过 ✓" : "吸附自检有 \(failures) 项失败")
    }

    static func scan() {
        Store.shared.load()
        let groups = DeskCategorizer.scanDesktop()
        let total = groups.values.reduce(0) { $0 + $1.count }

        print("桌面待归类: \(total) 项（只读，不会移动任何文件）")
        print("")
        if total == 0 {
            print("（桌面很干净）")
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

    /// 核心断言：往整理框里加条目之后，磁盘上的文件必须还在原处。
    static func selfTest() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(".cache/selftest", isDirectory: true)
        try? fm.removeItem(at: root)

        let sampleDir = root.appendingPathComponent("sample", isDirectory: true)
        try? fm.createDirectory(at: sampleDir, withIntermediateDirectories: true)

        let names = ["照片.png", "报告.pdf", "脚本.py", "未知.zzz", "文件夹"]
        for name in names {
            let url = sampleDir.appendingPathComponent(name)
            if name == "文件夹" {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try? "hello".write(to: url, atomically: true, encoding: .utf8)
            }
        }

        print("== 分类结果 ==")
        guard let urls = try? fm.contentsOfDirectory(at: sampleDir, includingPropertiesForKeys: nil) else {
            print("自检失败：无法列出测试目录")
            return
        }
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            print("  \(url.lastPathComponent)  ->  \(DeskCategorizer.category(for: url).rawValue)")
        }

        // 建一个临时整理框，把条目加进去
        print("")
        print("== 引用模式验证 ==")
        let box = Store.shared.addBox(name: "__selftest__")
        let added = Store.shared.addItems(urls, to: box.id)
        let addedAgain = Store.shared.addItems(urls, to: box.id)

        print("  新增引用: \(added)（去重后再加: \(addedAgain)，应为 0）")

        var stillThere = 0
        for url in urls where fm.fileExists(atPath: url.path) {
            stillThere += 1
        }
        print("  加完之后文件仍在原处: \(stillThere)/\(urls.count)")
        if stillThere != urls.count {
            print("  !! 失败：引用模式不应该动文件")
        }

        let stored = Store.shared.box(id: box.id)?.items.count ?? -1
        print("  框内条目数: \(stored)")

        // 保护规则
        let protected = Store.shared.addItems([Bundle.main.bundleURL], to: box.id)
        print("  尝试把程序自身加进框: 新增 \(protected)（应为 0）")

        Store.shared.removeBox(id: box.id)
        try? fm.removeItem(at: root)
        print("")
        print("自检结束")
    }
}
