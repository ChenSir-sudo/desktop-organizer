import AppKit
import SwiftUI

// MARK: - 宽容解码

/// 配置文件的字段会随版本增删。缺字段时用默认值补上，而不是整个配置读不出来。
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - 文件类型探测

extension URL {
    /// 一次 stat 同时拿到「存在」和「是不是目录」。
    var fileInfo: (exists: Bool, isDirectory: Bool) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue)
    }

    var isDirectory: Bool { fileInfo.isDirectory }
    var isExistingDirectory: Bool { fileInfo.exists && fileInfo.isDirectory }
}

// MARK: - 动效常量

/// 动画参数集中在这里，避免同一个 spring 参数散落在各个视图里各写一遍。
enum Motion {
    /// 页面切换、布局变化
    static let page = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// 条目增删
    static let items = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// 悬停淡入淡出
    static let hover = Animation.easeOut(duration: 0.18)
    /// 落点高亮
    static let dropTarget = Animation.easeOut(duration: 0.14)
    /// 文件夹接收高亮
    static let folderDrop = Animation.spring(response: 0.25, dampingFraction: 0.7)

    static let spring = (response: 0.34, damping: 0.86)
}
