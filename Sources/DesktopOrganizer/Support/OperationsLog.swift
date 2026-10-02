import Foundation

/// 文件操作审计日志。
///
/// 记录程序对用户文件做的**每一次改动**（移动、移到废纸篓）。之前只有拖拽日志，
/// 出问题时无法回答「这个目录是谁动的、什么时候动的」。
/// 出过事，所以补上。
enum OperationsLog {

    private static let url: URL = AppPaths.supportDirectory.appendingPathComponent("operations.log")
    private static let maxLines = 500

    /// 记一笔。追加写，保留最近若干行。
    static func append(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        existing += "[\(stamp)] \(message)\n"
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > maxLines {
            existing = lines.suffix(maxLines).joined(separator: "\n")
        }
        try? existing.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 日志文件位置，供界面提示用。
    static var fileURL: URL { url }
}
