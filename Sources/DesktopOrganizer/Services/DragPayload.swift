import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 整理框内部拖拽时携带的数据。
///
/// 故意**不**用文件 URL 作为载体：那样拖到访达会被当成真实文件复制，产生重复文件。
/// 用自定义类型，拖到访达/桌面就是「没有接收方」，可以明确定义成「移出整理框」。
struct DragPayload: Equatable {
    var boxID: UUID
    var itemID: UUID

    static let typeIdentifier = "com.chenziyang.desktoporganizer.item"
    static var utType: UTType { UTType(typeIdentifier) ?? .data }

    init(boxID: UUID, itemID: UUID) {
        self.boxID = boxID
        self.itemID = itemID
    }

    init?(string: String) {
        let parts = string.split(separator: "|")
        guard parts.count == 2,
              let boxID = UUID(uuidString: String(parts[0])),
              let itemID = UUID(uuidString: String(parts[1])) else { return nil }
        self.boxID = boxID
        self.itemID = itemID
    }

    var encoded: String { "\(boxID.uuidString)|\(itemID.uuidString)" }

    static func provider(for payload: DragPayload) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(payload.encoded.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: typeIdentifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func payload(from provider: NSItemProvider, completion: @escaping (DragPayload) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else { return }
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data, let string = String(data: data, encoding: .utf8),
                  let payload = DragPayload(string: string) else { return }
            DispatchQueue.main.async { completion(payload) }
        }
    }
}

/// 全局拖拽状态。必须共享，因为「从 A 框拖到 B 框」时，
/// B 框的视图看不到 A 框自己的 UI 状态。
final class DragSession: ObservableObject {
    static let shared = DragSession()

    /// 当前正在被拖动的条目
    @Published var payload: DragPayload?
    /// 是否已经被某个整理框接住了（用来区分「拖到别的框」和「拖出去丢掉」）
    @Published var handled = false

    func begin(_ payload: DragPayload) {
        self.payload = payload
        handled = false
    }

    func finish() {
        payload = nil
        handled = false
    }
}
