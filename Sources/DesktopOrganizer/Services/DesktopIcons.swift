import AppKit

/// 桌面图标的位置读写。
///
/// 这是新方案的地基：整理框不再"装"文件，只是在桌面上圈出一块区域，
/// **文件本身照旧留在 `~/Desktop/xxx`、也不隐藏**，程序只摆它们的图标坐标。
/// 所以程序对用户文件是**只读**的 —— 一个字节都不写。
///
/// 为什么用 Finder 的 AppleScript：macOS **没有**公开 API 读写桌面图标位置
/// （它们存在 .DS_Store 里，那是私有格式）。Finder 的脚本接口是唯一受支持的路子。
enum DesktopIcons {

    struct Icon: Equatable {
        /// Finder 里显示的名字。注意它**可能和磁盘上的文件名不同**
        /// （访达允许改显示名，实测桌面上就有这种情况），所以坐标读写一律用它。
        var name: String
        var isDirectory: Bool
        /// Finder 图标视图坐标：左上原点，单位是点。
        /// `.unknown` 表示这个图标从来没被手动摆过（Finder 返回 -1,-1）。
        var position: CGPoint
        /// 磁盘上的真实路径（`POSIX path`），用来做归类、打开等。
        var path: String

        var isPlaced: Bool { position.x >= 0 && position.y >= 0 }
        static let unknown = CGPoint(x: -1, y: -1)
    }

    // MARK: 桌面是否允许手动摆放

    /// 只有「排列方式 = 无」时手动坐标才有效。
    /// 用户一旦在访达里选了「按名称/日期/种类排序」，Finder 会覆盖所有坐标，
    /// 本功能会**静默失效** —— 所以每次整理前都要检查并提示。
    static var isManuallyArranged: Bool {
        let out = run("""
        tell application "Finder"
            try
                return (arrangement of icon view options of window of desktop) as text
            on error
                return "unknown"
            end try
        end tell
        """)
        return out == "not arranged"
    }

    // MARK: 读

    /// 读出桌面上所有图标的当前坐标。
    static func readAll() -> [Icon] {
        // 注意：必须先把名字列表**存进变量**再遍历。
        // 直接 `repeat with n in (name of every file of desktop)` 时 n 是个引用，
        // `(n as text)` 会抛 -1700（实测踩过）。
        let script = """
        tell application "Finder"
            set out to ""
            set fileNames to name of every file of desktop
            repeat with n in fileNames
                try
                    set nm to (n as text)
                    set p to position of file nm of desktop
                    set out to out & "F" & tab & nm & tab & (item 1 of p) & tab & (item 2 of p) & tab & (POSIX path of (file nm of desktop as alias)) & linefeed
                end try
            end repeat
            set folderNames to name of every folder of desktop
            repeat with n in folderNames
                try
                    set nm to (n as text)
                    set p to position of folder nm of desktop
                    set out to out & "D" & tab & nm & tab & (item 1 of p) & tab & (item 2 of p) & tab & (POSIX path of (folder nm of desktop as alias)) & linefeed
                end try
            end repeat
            return out
        end tell
        """
        return parse(run(script))
    }

    private static func parse(_ output: String) -> [Icon] {
        var icons: [Icon] = []
        for line in output.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5 else { continue }
            let isDirectory = f[0] == "D"
            guard let x = Double(f[2]), let y = Double(f[3]) else { continue }
            icons.append(Icon(
                name: f[1],
                isDirectory: isDirectory,
                position: CGPoint(x: x, y: y),
                path: f[4]
            ))
        }
        return icons
    }

    // MARK: 写

    /// 把一个图标摆到指定坐标。返回是否成功。
    @discardableResult
    static func setPosition(of icon: Icon, to point: CGPoint) -> Bool {
        setPositions([(icon, point)]) == 1
    }

    /// 批量摆放 —— 一次 osascript 调用里全部做完，避免 N 次进程启动。
    /// 返回成功摆好的个数。
    @discardableResult
    static func setPositions(_ moves: [(icon: Icon, point: CGPoint)]) -> Int {
        guard !moves.isEmpty else { return 0 }
        var lines: [String] = []
        for (icon, point) in moves {
            // 名字里的单引号/反斜杠要转义，否则会拼出坏脚本
            let escaped = icon.name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let kind = icon.isDirectory ? "folder" : "file"
            lines.append("""
                try
                    set position of \(kind) "\(escaped)" of desktop to {\(Int(point.x.rounded())), \(Int(point.y.rounded()))}
                    set ok to ok + 1
                end try
            """)
        }
        let script = """
        tell application "Finder"
            set ok to 0
            \(lines.joined(separator: "\n"))
            return ok
        end tell
        """
        return Int(run(script)) ?? 0
    }

    // MARK: 执行

    /// 跑一段 AppleScript，返回去掉首尾空白的输出。
    /// 失败（没授权 / Finder 没响应）返回空串。
    private static func run(_ script: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // 从 stdin 喂脚本：`-e` 传多行不可靠（实测会静默失败）
        process.arguments = []

        let input = Pipe()
        let pipe = Pipe()
        process.standardInput = input
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }

        input.fileHandleForWriting.write(Data(script.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
