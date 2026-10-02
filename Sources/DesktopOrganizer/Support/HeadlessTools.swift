import AppKit
import UniformTypeIdentifiers

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

        // 缩放吸附：固定左上角，动的只有右边缘（maxX）和下边缘（minY）
        print("")
        print("== 缩放吸附 ==")
        let r1 = SnapEngine.snapResize(
            frame: CGRect(x: 100, y: 300, width: 303, height: 100),
            others: [CGRect(x: 400, y: 0, width: 200, height: 200)],
            screen: screen,
            minSize: CGSize(width: 240, height: 160)
        )
        print("  引导线: \(describe(r1.guides))")
        check("右边缘吸到另一框左边缘后的宽度", r1.size.width, 300)
        check("给出竖引导线", CGFloat(r1.guides.filter { $0.axis == .vertical }.count), 1)

        let r2 = SnapEngine.snapResize(
            frame: CGRect(x: 100, y: 8, width: 300, height: 300),
            others: [], screen: screen,
            minSize: CGSize(width: 240, height: 160)
        )
        print("  引导线: \(describe(r2.guides))")
        check("下边缘吸到屏幕底后的高度", r2.size.height, 308)
        check("给出横引导线", CGFloat(r2.guides.filter { $0.axis == .horizontal }.count), 1)

        let r3 = SnapEngine.snapResize(
            frame: CGRect(x: 100, y: 300, width: 700, height: 100),
            others: [], screen: screen,
            minSize: CGSize(width: 240, height: 160)
        )
        check("离得远时不吸附（宽度不变）", r3.size.width, 700)
        check("离得远时没有引导线", CGFloat(r3.guides.count), 0)

        let r4 = SnapEngine.snapResize(
            frame: CGRect(x: 100, y: 300, width: 50, height: 50),
            others: [], screen: screen,
            minSize: CGSize(width: 240, height: 160)
        )
        check("小于最小尺寸时宽度被夹住", r4.size.width, 240)
        check("小于最小尺寸时高度被夹住", r4.size.height, 160)

        print("")
        print(failures == 0 ? "吸附自检全部通过 ✓" : "吸附自检有 \(failures) 项失败")
    }

    /// 单独验证隐藏标志的两个方向，排除其它逻辑干扰。
    static func hideTest() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".cache/hidetest")
        try? fm.removeItem(at: root)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("样本 测试.txt")
        try? "x".write(to: file, atomically: true, encoding: .utf8)

        print("初始 isHidden = \(HiddenFlag.isHidden(file))")

        let r1 = HiddenFlag.setHidden(true, for: file)
        print("setHidden(true)  返回 \(r1)   isHidden = \(HiddenFlag.isHidden(file))")

        let r2 = HiddenFlag.setHidden(false, for: file)
        print("setHidden(false) 返回 \(r2)   isHidden = \(HiddenFlag.isHidden(file))")

        // 直接看 BSD 标志，绕开 Foundation
        func flags() -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/stat")
            p.arguments = ["-f", "%Sf", file.path]
            let pipe = Pipe(); p.standardOutput = pipe
            try? p.run(); p.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
        }
        print("stat 标志位: \(flags())")

        try? fm.removeItem(at: root)
    }

    /// 验证拖拽落地时「从 NSItemProvider 里取文件 URL」这条路径，
    /// 分别拿一个文件夹和一个 .md 文件对比。
    static func dropTest() {
        let desktop = AppPaths.desktopDirectory
        let samples = [
            desktop.appendingPathComponent("CONTEXT-领域模型.md"),
            desktop.appendingPathComponent("公司企业画像与业务.md"),
            desktop.appendingPathComponent("TradePilot"),
        ]
        for url in samples {
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("跳过（不存在）: \(url.lastPathComponent)")
                continue
            }
            print("== \(url.lastPathComponent) \(isDirectory(url) ? "[文件夹]" : "[文件]") ==")
            guard let provider = NSItemProvider(contentsOf: url) else {
                print("   !! NSItemProvider(contentsOf:) 返回 nil")
                continue
            }
            print("   registeredTypes: \(provider.registeredTypeIdentifiers)")
            print("   hasItemConformingToTypeIdentifier(fileURL): \(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))")

            let sem1 = DispatchSemaphore(value: 0)
            provider.loadObject(ofClass: NSURL.self) { object, error in
                print("   loadObject(NSURL) -> \(object.map { "\($0)" } ?? "nil")  err=\(error?.localizedDescription ?? "-")")
                sem1.signal()
            }
            _ = sem1.wait(timeout: .now() + 3)

            let sem2 = DispatchSemaphore(value: 0)
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                var desc = "nil"
                if let data = item as? Data, let s = String(data: data, encoding: .utf8) { desc = "Data -> \(s)" }
                else if let u = item as? URL { desc = "URL -> \(u.path)" }
                else if let u = item as? NSURL { desc = "NSURL -> \(u.path ?? "-")" }
                else if let item { desc = "\(type(of: item))" }
                print("   loadItem(fileURL) -> \(desc)  err=\(error?.localizedDescription ?? "-")")
                sem2.signal()
            }
            _ = sem2.wait(timeout: .now() + 3)
            print("")
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var d: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &d)
        return d.boolValue
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
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            if !ok { failures += 1 }
            print("  \(ok ? "OK " : "!! ") \(name)")
        }
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

        // 关键新语义：进框 -> 原位置隐藏；出框 -> 原位置恢复
        print("")
        print("== 原位置隐藏 / 恢复 ==")
        let target = sampleDir.appendingPathComponent("照片.png")
        print("  加框后 隐藏标志: \(HiddenFlag.isHidden(target))（应为 true）")
        print("  路径是否不变: \(target.path)")
        print("  文件是否仍可按原路径读取: \(FileManager.default.fileExists(atPath: target.path))")

        let itemID = Store.shared.box(id: box.id)?.items.first(where: { $0.path == target.path })?.id
        if let itemID {
            Store.shared.removeItems([itemID], from: box.id)
            print("  从框中移除后 隐藏标志: \(HiddenFlag.isHidden(target))（应为 false）")
        } else {
            print("  !! 找不到刚加入的条目")
        }

        // 框内重排 + 跨框转移
        print("")
        print("== 重排 / 跨框转移 ==")
        let orderBefore = Store.shared.box(id: box.id)?.items.map(\.name) ?? []
        if let firstID = Store.shared.box(id: box.id)?.items.first?.id {
            Store.shared.moveItems(in: box.id, itemIDs: [firstID], to: 2)
        }
        let orderAfter = Store.shared.box(id: box.id)?.items.map(\.name) ?? []

        // 语义：拖到「原第 3 项」的位置 = 插到那一项**之前**。
        // [A,B,C,…] 把 A 拖到 C 的位置 -> [B,A,C,…]
        check("单个重排插到目标项之前",
              orderAfter.count == orderBefore.count
              && orderAfter[0] == orderBefore[1]
              && orderAfter[1] == orderBefore[0]
              && orderAfter[2] == orderBefore[2])
        check("重排没有丢条目", Set(orderAfter) == Set(orderBefore))

        // 多选**向下**拖：这是之前偏移 k 格的那个 bug。
        // [A,B,C,D,E] 选中 [A,B] 拖到 D(下标 3) 的位置 -> 期望 [C,A,B,D,E]
        let before = Store.shared.box(id: box.id)?.items.map(\.name) ?? []
        let batchIDs = Array((Store.shared.box(id: box.id)?.items ?? []).prefix(2).map(\.id))
        Store.shared.moveItems(in: box.id, itemIDs: batchIDs, to: 3)
        let after = Store.shared.box(id: box.id)?.items.map(\.name) ?? []
        check("多选向下拖不偏移（插到目标项之前）",
              after.count == before.count
              && after[0] == before[2]
              && after[1] == before[0]
              && after[2] == before[1]
              && after[3] == before[3])
        check("多选重排没有丢条目", Set(after) == Set(before))

        // 多选**向上**拖
        let upBefore = Store.shared.box(id: box.id)?.items.map(\.name) ?? []
        let upIDs = Array((Store.shared.box(id: box.id)?.items ?? []).suffix(2).map(\.id))
        Store.shared.moveItems(in: box.id, itemIDs: upIDs, to: 1)
        let upAfter = Store.shared.box(id: box.id)?.items.map(\.name) ?? []
        check("多选向上拖插到目标项之前",
              upAfter.count == upBefore.count
              && upAfter[0] == upBefore[0]
              && upAfter[1] == upBefore[upBefore.count - 2]
              && upAfter[2] == upBefore[upBefore.count - 1])
        check("多选向上拖没有丢条目", Set(upAfter) == Set(upBefore))

        let targetBox = Store.shared.addBox(name: "__selftest_target__")
        if let moveID = Store.shared.box(id: box.id)?.items.first?.id {
            let moved = Store.shared.transferItems([moveID], from: box.id, to: targetBox.id, at: 0)
            let inTarget = Store.shared.box(id: targetBox.id)?.items.count ?? 0
            check("跨框转移成功", moved && inTarget == 1)
            // 转移过去之后原位置仍然应该是隐藏的（didHide 跟着条目走）
            if let path = Store.shared.box(id: targetBox.id)?.items.first?.path {
                check("转移后仍保持隐藏", HiddenFlag.isHidden(URL(fileURLWithPath: path)))
            }
        }
        Store.shared.removeBox(id: targetBox.id)

        // 删框要把剩下的全部恢复显示
        Store.shared.removeBox(id: box.id)
        var leftoverHidden = 0
        for url in urls where HiddenFlag.isHidden(url) { leftoverHidden += 1 }
        print("  删除整理框后仍被隐藏的数量: \(leftoverHidden)（应为 0）")


        try? fm.removeItem(at: root)
        // 移入文件夹（拖到文件夹图标上）—— 这是唯一真正移动文件的操作
        print("")
        print("== 移入文件夹 ==")
        let inbox = root.appendingPathComponent("收件箱", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let loose = staging.appendingPathComponent("待归档.txt")
        try? "x".write(to: loose, atomically: true, encoding: .utf8)

        let moved = FileActions.move([loose], into: inbox)
        check("移入成功", moved.moved.count == 1 && moved.failures.isEmpty)
        check("原位置已不存在", !fm.fileExists(atPath: loose.path))
        check("已出现在目标文件夹", fm.fileExists(atPath: inbox.appendingPathComponent("待归档.txt").path))

        // 同名冲突不覆盖
        try? "y".write(to: loose, atomically: true, encoding: .utf8)
        let again = FileActions.move([loose], into: inbox)
        check("同名时不覆盖，自动改名", again.moved.first?.to.lastPathComponent == "待归档 2.txt")

        // 不能把文件夹移进它自己
        let selfMove = FileActions.move([inbox], into: inbox.appendingPathComponent("子目录", isDirectory: true))
        check("拒绝移进子目录", selfMove.moved.isEmpty && !selfMove.failures.isEmpty)

        // 受保护路径
        let protectedMove = FileActions.move([Bundle.main.bundleURL], into: inbox)
        check("拒绝搬移程序自身", protectedMove.moved.isEmpty)

        // 回归：同一个文件被多个整理框引用时，最后一个框移除才该恢复显示
        print("")
        print("== 多框引用同一个文件 ==")
        let shared = staging.appendingPathComponent("共享文件.txt")
        try? "z".write(to: shared, atomically: true, encoding: .utf8)
        let boxA = Store.shared.addBox(name: "__ref_A__")
        let boxB = Store.shared.addBox(name: "__ref_B__")
        Store.shared.addItems([shared], to: boxA.id)
        Store.shared.addItems([shared], to: boxB.id)
        check("两个框都引用了它", Store.shared.box(id: boxA.id)?.items.count == 1
              && Store.shared.box(id: boxB.id)?.items.count == 1)
        check("加入后是隐藏的", HiddenFlag.isHidden(shared))

        if let idA = Store.shared.box(id: boxA.id)?.items.first?.id {
            Store.shared.removeItems([idA], from: boxA.id)
        }
        check("从 A 移除后仍保持隐藏（B 还引用着）", HiddenFlag.isHidden(shared))

        if let idB = Store.shared.box(id: boxB.id)?.items.first?.id {
            Store.shared.removeItems([idB], from: boxB.id)
        }
        check("从 B 移除后恢复显示", !HiddenFlag.isHidden(shared))

        Store.shared.removeBox(id: boxA.id)
        Store.shared.removeBox(id: boxB.id)
        try? fm.removeItem(at: shared)

        // 回归：给配置结构加字段时，旧配置必须还能解码。
        // Swift 合成的 init(from:) 对非可选属性一律要求键存在（即使有默认值），
        // 一旦漏掉这个，旧配置整份解码失败 → load() 的 try? 静默吞掉 → save() 写回空配置。
        print("")
        print("== 配置宽容解码 ==")
        let empty = Data("{}".utf8)
        check("BoxConfig 能从空对象解码", (try? JSONDecoder().decode(BoxConfig.self, from: empty)) != nil)
        check("Preferences 能从空对象解码", (try? JSONDecoder().decode(Preferences.self, from: empty)) != nil)
        check("BoxItem 能从只有 path 的对象解码",
              (try? JSONDecoder().decode(BoxItem.self, from: Data(#"{"path":"/tmp/x"}"#.utf8))) != nil)

        // 只有一个未知字段的旧对象也必须能读
        let legacy = Data(#"{"name":"旧框","folderPath":"/tmp/legacy"}"#.utf8)
        if let decoded = try? JSONDecoder().decode(BoxConfig.self, from: legacy) {
            check("1.0 的 folderPath 被读成 legacyFolderPath", decoded.legacyFolderPath == "/tmp/legacy")
            check("缺 items 时默认为空", decoded.items.isEmpty)
        } else {
            check("1.0 格式的 BoxConfig 能解码", false)
        }

        // 回归：内部拖拽载荷必须能往返
        // （真实的 NSPasteboard 往返没法在这里测 —— NSItemProvider 不实现
        //  NSPasteboardWriting，写不进 pasteboard。这里测编解码和类型标识。）
        print("")
        print("== 内部拖拽载荷 ==")
        let idA = UUID(), idB = UUID(), dragBox = UUID()
        let payload = DragPayload(boxID: dragBox, itemIDs: [idA, idB])
        check("编码后能解回框 ID", DragPayload(string: payload.encoded)?.boxID == dragBox)
        check("编码后能解回两个条目",
              DragPayload(string: payload.encoded)?.itemIDs == [idA, idB])
        check("空条目解不出来", DragPayload(string: "\(dragBox.uuidString)|") == nil)
        check("乱码解不出来", DragPayload(string: "not-a-payload") == nil)
        check("粘贴板类型与载荷类型标识一致",
              DragPayload.pasteboardType.rawValue == DragPayload.typeIdentifier)


        // 复现用户的真实场景：父目录在一个框、子目录在另一个框，
        // 然后把子目录从一个框拖到另一个框（Commands.transfer 走的就是这条）。
        // 断言：两个目录和里面的文件都必须原封不动。
        print("")
        print("== 跨框转移不得动到文件 ==")
        let ws = staging.appendingPathComponent("workspace")
        let mn = ws.appendingPathComponent("main_note")
        try? fm.createDirectory(at: mn, withIntermediateDirectories: true)
        let inner = mn.appendingPathComponent("笔记.md")
        try? "# 内容".write(to: inner, atomically: true, encoding: .utf8)

        let boxP = Store.shared.addBox(name: "__parent__")
        let boxC = Store.shared.addBox(name: "__child__")
        Store.shared.addItems([ws], to: boxP.id)
        Store.shared.addItems([mn], to: boxC.id)
        check("两个目录都在", fm.fileExists(atPath: ws.path) && fm.fileExists(atPath: mn.path))

        if let childID = Store.shared.box(id: boxC.id)?.items.first?.id {
            // 等价于从子目录所在的框拖到父目录所在的框
            let moved = Store.shared.transferItems([childID], from: boxC.id, to: boxP.id, at: 0)
            check("转移成功", moved)
        }
        check("转移后父目录仍在", fm.fileExists(atPath: ws.path))
        check("转移后子目录仍在", fm.fileExists(atPath: mn.path))
        check("转移后里面的文件仍在", fm.fileExists(atPath: inner.path))
        check("转移后子目录还在父目录里面", mn.path.hasPrefix(ws.path + "/"))

        // 反向：再拖回去
        if let itemID = Store.shared.box(id: boxP.id)?.items.first(where: { $0.path == mn.path })?.id {
            _ = Store.shared.transferItems([itemID], from: boxP.id, to: boxC.id, at: 0)
        }
        check("反向转移后文件仍在", fm.fileExists(atPath: inner.path))

        Store.shared.removeBox(id: boxP.id)
        Store.shared.removeBox(id: boxC.id)
        try? fm.removeItem(at: ws)

        print("")
        print(failures == 0 ? "自检结束：全部通过 ✓" : "自检结束：有 \(failures) 项失败 ✗")
    }
}
