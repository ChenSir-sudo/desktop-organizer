import AppKit

/// 安全测试：验证程序**不可能损坏或丢失用户的文件**。
///
/// 用法：
///   DesktopOrganizer --safetest              只跑不依赖外部宗卷的用例
///   DesktopOrganizer --safetest /Volumes/XX  额外跑「跨宗卷移动被拒绝」的用例
///
/// 每一条都对应一条声称的保证，而不是泛泛地"跑一下看看"。
enum SafetyTests {

    static func run(extraVolume: String?) {
        let fm = FileManager.default
        var failures = 0
        var checks = 0

        func check(_ name: String, _ ok: Bool) {
            checks += 1
            if !ok { failures += 1 }
            print("  \(ok ? "OK " : "!! ") \(name)")
        }

        let root = AppPaths.supportDirectory.appendingPathComponent("safetest")
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func makeDir(_ name: String) -> URL {
            let url = root.appendingPathComponent(name)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func makeFile(_ dir: URL, _ name: String, _ body: String = "内容") -> URL {
            let url = dir.appendingPathComponent(name)
            try? body.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func read(_ url: URL) -> String? {
            try? String(contentsOf: url, encoding: .utf8)
        }

        // MARK: 保证一：移动成功时内容完整

        print("== 保证：移动成功 = 内容完整 ==")
        do {
            let from = makeDir("m1_src")
            let into = makeDir("m1_dst")
            let dir = from.appendingPathComponent("vault")
            try? fm.createDirectory(at: dir.appendingPathComponent("notes"), withIntermediateDirectories: true)
            try? "笔记内容".write(to: dir.appendingPathComponent("notes/a.md"), atomically: true, encoding: .utf8)

            let outcome = FileActions.move([dir], into: into)
            check("移动成功", outcome.moved.count == 1 && outcome.failures.isEmpty)
            check("源位置已不存在", !fm.fileExists(atPath: dir.path))
            let landed = into.appendingPathComponent("vault/notes/a.md")
            check("目标位置内容完整", read(landed) == "笔记内容")
        }

        // MARK: 保证二：移动失败时源文件原封不动

        print("")
        print("== 保证：移动失败 = 源文件原封不动 ==")
        do {
            let from = makeDir("m2_src")
            let into = makeDir("m2_dst_readonly")
            let file = makeFile(from, "重要.txt", "非常重要的内容")

            // 把目标目录设成只读，强制 moveItem 失败
            try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: into.path)
            let outcome = FileActions.move([file], into: into)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: into.path)

            check("移动被报告为失败", !outcome.failures.isEmpty)
            check("源文件仍在原位置", fm.fileExists(atPath: file.path))
            check("源文件内容没变", read(file) == "非常重要的内容")
        }

        // MARK: 保证三：跨宗卷移动被拒绝（需要外部宗卷）

        print("")
        print("== 保证：跨宗卷移动被拒绝 ==")
        if let extraVolume, fm.fileExists(atPath: extraVolume) {
            let from = makeDir("m3_src")
            let file = makeFile(from, "跨盘.txt", "跨盘内容")
            let outcome = FileActions.move([file], into: URL(fileURLWithPath: extraVolume))

            check("被拒绝并给出原因", outcome.failures.contains { $0.reason.contains("不同磁盘") })
            check("源文件仍在原位置", fm.fileExists(atPath: file.path))
            check("源文件内容没变", read(file) == "跨盘内容")
            check("目标位置没有留下任何东西",
                  !fm.fileExists(atPath: URL(fileURLWithPath: extraVolume).appendingPathComponent("跨盘.txt").path))
        } else {
            print("  （未提供外部宗卷，跳过）")
        }

        // MARK: 保证四：拒绝把文件夹移进它自己

        print("")
        print("== 保证：拒绝把文件夹移进它自己 ==")
        do {
            let outer = makeDir("m4_outer")
            let inner = outer.appendingPathComponent("inner")
            try? fm.createDirectory(at: inner, withIntermediateDirectories: true)
            try? "x".write(to: inner.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)

            let outcome = FileActions.move([outer], into: inner)
            check("被拒绝", !outcome.failures.isEmpty)
            check("文件夹结构完好", fm.fileExists(atPath: inner.appendingPathComponent("keep.txt").path))
        }

        // MARK: 保证五：受保护路径一律不碰

        print("")
        print("== 保证：受保护路径一律不碰 ==")
        do {
            let into = makeDir("m5_dst")
            let protected = [AppPaths.desktopDirectory, AppPaths.supportDirectory,
                             URL(fileURLWithPath: NSHomeDirectory()), Bundle.main.bundleURL]
            var allRefused = true
            for url in protected where FileActions.move([url], into: into).moved.isEmpty == false {
                allRefused = false
            }
            check("桌面 / 配置目录 / 主目录 / 程序自身 全部拒绝", allRefused)
            check("桌面仍在", fm.fileExists(atPath: AppPaths.desktopDirectory.path))
            check("配置目录仍在", fm.fileExists(atPath: AppPaths.supportDirectory.path))
        }

        // MARK: 保证六：隐藏/取消隐藏不改内容、不改位置

        print("")
        print("== 保证：隐藏只改标志位 ==")
        do {
            let dir = makeDir("m6")
            let file = makeFile(dir, "被隐藏.txt", "原始内容")
            let before = (read(file), fm.fileExists(atPath: file.path))

            _ = HiddenFlag.setHidden(true, for: file)
            check("隐藏后仍存在", fm.fileExists(atPath: file.path))
            check("隐藏后内容没变", read(file) == before.0)
            check("隐藏标志确实生效", HiddenFlag.isHidden(file))

            _ = HiddenFlag.setHidden(false, for: file)
            check("取消隐藏后仍存在", fm.fileExists(atPath: file.path))
            check("取消隐藏后内容没变", read(file) == before.0)
            check("隐藏标志已撤销", !HiddenFlag.isHidden(file))
        }

        // MARK: 保证七：从整理框增删条目、删框 —— 一个文件都不会动

        print("")
        print("== 保证：整理框的增删不动文件 ==")
        do {
            let dir = makeDir("m7")
            let file = makeFile(dir, "参照.txt", "参照内容")
            let box = Store.shared.addBox(name: "__safety__")
            Store.shared.addItems([file], to: box.id)
            check("加入后文件仍在", fm.fileExists(atPath: file.path))

            if let itemID = Store.shared.box(id: box.id)?.items.first?.id {
                Store.shared.removeItems([itemID], from: box.id)
            }
            check("移除条目后文件仍在", fm.fileExists(atPath: file.path))
            check("移除条目后内容没变", read(file) == "参照内容")

            Store.shared.addItems([file], to: box.id)
            Store.shared.removeBox(id: box.id)
            check("删掉整理框后文件仍在", fm.fileExists(atPath: file.path))
            check("删掉整理框后内容没变", read(file) == "参照内容")
        }

        // MARK: 保证八：搬移失败时条目不能白丢

        print("")
        print("== 保证：搬移失败不丢条目 ==")
        do {
            let dir = makeDir("m8")
            let file = makeFile(dir, "搬不动.txt", "内容")
            let target = makeDir("m8_readonly")
            try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: target.path)

            let box = Store.shared.addBox(name: "__m8__")
            Store.shared.addItems([file], to: box.id)
            let before = Store.shared.box(id: box.id)?.items.count ?? 0

            Commands.moveItemsIntoFolder(
                (Store.shared.box(id: box.id)?.items ?? []).map(\.id),
                in: box.id, folder: target
            )
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)

            let after = Store.shared.box(id: box.id)?.items.count ?? 0
            check("搬移失败时条目**不该**被摘掉", before > 0 && after == before)
            check("文件仍在原位置", fm.fileExists(atPath: file.path))
            check("内容没变", read(file) == "内容")
            Store.shared.removeBox(id: box.id)
        }

        // MARK: 保证九：不留「文件被隐藏、却没有任何记录」的黑洞

        print("")
        print("== 保证：隐藏必有记录 ==")
        do {
            let dir = makeDir("m9")
            let file = makeFile(dir, "记账.txt", "内容")
            let box = Store.shared.addBox(name: "__m9__")
            Store.shared.addItems([file], to: box.id)

            let isHiddenNow = HiddenFlag.isHidden(file)
            let hasRecord = Store.shared.hiddenPaths.contains(file.standardizedFileURL.path)
            check("文件被隐藏时一定有 hiddenPaths 记录", !isHiddenNow || hasRecord)

            // 反向：条目记着 didHide 的，必须都能在 hiddenPaths 里找到
            var consistent = true
            for b in Store.shared.boxes {
                for item in b.items where item.didHide {
                    if !Store.shared.hiddenPaths.contains(
                        URL(fileURLWithPath: item.path).standardizedFileURL.path) {
                        consistent = false
                    }
                }
            }
            check("所有 didHide 条目都在 hiddenPaths 里", consistent)

            Store.shared.removeBox(id: box.id)
            check("删框后记录也清干净",
                  !Store.shared.hiddenPaths.contains(file.standardizedFileURL.path))
            check("删框后文件仍在", fm.fileExists(atPath: file.path))
        }

        // MARK: 保证十：移到废纸篓后不能留失效引用

        print("")
        print("== 保证：移到废纸篓后清干净引用 ==")
        do {
            let dir = makeDir("m10")
            let file = makeFile(dir, "要删的.txt", "内容")
            let boxA = Store.shared.addBox(name: "__m10a__")
            let boxB = Store.shared.addBox(name: "__m10b__")
            Store.shared.addItems([file], to: boxA.id)
            Store.shared.addItems([file], to: boxB.id)
            check("两个框都引用了它",
                  Store.shared.box(id: boxA.id)?.items.count == 1
                  && Store.shared.box(id: boxB.id)?.items.count == 1)

            let trashed = FileActions.moveToTrash(file)
            check("已移进废纸篓", trashed && !fm.fileExists(atPath: file.path))

            let removed = Store.shared.removeAllReferences(toPath: file.path)
            check("两个框里的引用都清掉了（不是只清一个）", removed == 2)
            check("框 A 不再留着失效条目", Store.shared.box(id: boxA.id)?.items.isEmpty == true)
            check("框 B 不再留着失效条目", Store.shared.box(id: boxB.id)?.items.isEmpty == true)
            check("隐藏记录也清了",
                  !Store.shared.hiddenPaths.contains(file.standardizedFileURL.path))

            Store.shared.removeBox(id: boxA.id)
            Store.shared.removeBox(id: boxB.id)
        }

        // MARK: 保证十一：一键清除失效条目

        print("")
        print("== 保证：一键清失效条目 ==")
        do {
            let dir = makeDir("m11")
            let gone = makeFile(dir, "待会删掉.txt", "x")
            let kept = makeFile(dir, "保留.txt", "y")
            let box = Store.shared.addBox(name: "__m11__")
            Store.shared.addItems([gone, kept], to: box.id)
            try? fm.removeItem(at: gone)          // 模拟在访达里被删掉

            let cleared = Store.shared.removeBrokenReferences()
            check("清掉了 1 个失效条目", cleared == 1)
            check("有效条目保留", Store.shared.box(id: box.id)?.items.count == 1)
            check("保留的那个文件没被动过", fm.fileExists(atPath: kept.path))
            Store.shared.removeBox(id: box.id)
        }

        print("")
        print(failures == 0
              ? "安全测试：全部通过 ✓（\(checks) 项）"
              : "安全测试：有 \(failures) 项失败 ✗（共 \(checks) 项）")
        if failures > 0 { exit(1) }
    }
}
