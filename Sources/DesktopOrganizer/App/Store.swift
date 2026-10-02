import AppKit
import Combine

// MARK: - 背景材质

enum BoxMaterial: String, Codable, CaseIterable, Identifiable {
    case hud
    case sidebar
    case popover
    case underWindow
    case fullScreen
    case menuBackground
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hud: return "毛玻璃 · 常规"
        case .sidebar: return "毛玻璃 · 侧边栏"
        case .popover: return "毛玻璃 · 浮层"
        case .underWindow: return "毛玻璃 · 窗口底"
        case .fullScreen: return "毛玻璃 · 全屏"
        case .menuBackground: return "毛玻璃 · 菜单"
        case .solid: return "纯色 · 无模糊"
        }
    }

    var isBlurred: Bool { self != .solid }

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hud: return .hudWindow
        case .sidebar: return .sidebar
        case .popover: return .popover
        case .underWindow: return .underWindowBackground
        case .fullScreen: return .fullScreenUI
        case .menuBackground: return .menu
        case .solid: return .contentBackground
        }
    }
}

// MARK: - 整理框配置

struct BoxConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "新建整理框"
    var folderPath: String = ""
    var frameX: Double = 0
    var frameY: Double = 0
    var frameW: Double = 300
    var frameH: Double = 360
    var opacity: Double = 0.88
    var material: BoxMaterial = .hud
    var cornerRadius: Double = 20
    var floatOnTop: Bool = true
    var accentHex: String = "0A84FF"

    init() {}

    // 宽容解码：旧配置缺少字段时用默认值补上，避免升级后配置读不出来。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        id = value(.id, UUID())
        name = value(.name, "整理框")
        folderPath = value(.folderPath, "")
        frameX = value(.frameX, 0)
        frameY = value(.frameY, 0)
        frameW = value(.frameW, 300)
        frameH = value(.frameH, 360)
        opacity = value(.opacity, 0.88)
        material = value(.material, .hud)
        cornerRadius = value(.cornerRadius, 20)
        floatOnTop = value(.floatOnTop, true)
        accentHex = value(.accentHex, "0A84FF")
    }

    var folderURL: URL {
        URL(fileURLWithPath: folderPath.isEmpty ? AppPaths.defaultRootDirectory.path : folderPath)
    }

    var frame: CGRect {
        get { CGRect(x: frameX, y: frameY, width: frameW, height: frameH) }
        set {
            frameX = Double(newValue.origin.x)
            frameY = Double(newValue.origin.y)
            frameW = Double(newValue.size.width)
            frameH = Double(newValue.size.height)
        }
    }
}

// MARK: - 全局偏好

struct Preferences: Codable, Equatable {
    var rootPath: String = ""
    var defaultOpacity: Double = 0.88
    var defaultMaterial: BoxMaterial = .hud
    var defaultCornerRadius: Double = 20
    var defaultFloatOnTop: Bool = true
    var confirmBeforeOrganize: Bool = true

    var rootURL: URL {
        URL(fileURLWithPath: rootPath.isEmpty ? AppPaths.defaultRootDirectory.path : rootPath)
    }
}

// MARK: - 落盘结构

private struct AppConfig: Codable {
    var version: Int = 1
    var boxes: [BoxConfig] = []
    var prefs: Preferences = Preferences()
}

// MARK: - Store

final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var boxes: [BoxConfig] = []
    @Published var prefs: Preferences = Preferences() {
        didSet { scheduleSave() }
    }

    private var saveWorkItem: DispatchWorkItem?
    private var isLoading = false

    private init() {}

    // MARK: 读写

    func load() {
        isLoading = true
        defer { isLoading = false }

        if let data = try? Data(contentsOf: AppPaths.configURL),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            boxes = config.boxes
            prefs = config.prefs
        }

        if prefs.rootPath.isEmpty {
            prefs.rootPath = AppPaths.defaultRootDirectory.path
        }
        // 修正历史配置里可能出现的空路径
        for index in boxes.indices where boxes[index].folderPath.isEmpty {
            boxes[index].folderPath = defaultFolderURL(for: boxes[index].name).path
        }
        if boxes.isEmpty {
            createStarterBoxes()
        }
        save()
    }

    func save() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let config = AppConfig(version: 1, boxes: boxes, prefs: prefs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: AppPaths.configURL, options: .atomic)
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    // MARK: 查询

    func box(id: UUID) -> BoxConfig? {
        boxes.first { $0.id == id }
    }

    func box(withFolder path: String) -> BoxConfig? {
        boxes.first { $0.folderPath == path }
    }

    func defaultFolderURL(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return prefs.rootURL.appendingPathComponent(safe, isDirectory: true)
    }

    // MARK: 增删改

    func update(id: UUID, _ mutate: (inout BoxConfig) -> Void) {
        guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&boxes[index])
        scheduleSave()
    }

    @discardableResult
    func addBox(name: String, folder: URL?, frame: CGRect? = nil) -> BoxConfig {
        var box = BoxConfig()
        box.name = name
        box.folderPath = (folder ?? defaultFolderURL(for: name)).path
        box.opacity = prefs.defaultOpacity
        box.material = prefs.defaultMaterial
        box.cornerRadius = prefs.defaultCornerRadius
        box.floatOnTop = prefs.defaultFloatOnTop
        box.accentHex = AccentPalette.all[boxes.count % AccentPalette.all.count]

        let size = CGSize(width: 300, height: 360)
        let target = frame ?? LayoutEngine.nextFreeFrame(size: size, existing: boxes.map(\.frame))
        box.frame = target

        try? FileManager.default.createDirectory(at: box.folderURL, withIntermediateDirectories: true)

        boxes.append(box)
        scheduleSave()
        return box
    }

    func removeBox(id: UUID) {
        boxes.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: 首次启动

    private func createStarterBoxes() {
        try? FileManager.default.createDirectory(at: prefs.rootURL, withIntermediateDirectories: true)
        let starters = ["待整理", "图片", "文档"]
        var placed: [CGRect] = []
        for name in starters {
            var box = BoxConfig()
            box.name = name
            box.folderPath = defaultFolderURL(for: name).path
            box.accentHex = AccentPalette.all[placed.count % AccentPalette.all.count]
            let frame = LayoutEngine.nextFreeFrame(size: CGSize(width: 300, height: 360), existing: placed)
            box.frame = frame
            placed.append(frame)
            try? FileManager.default.createDirectory(at: box.folderURL, withIntermediateDirectories: true)
            boxes.append(box)
        }
        save()
    }
}

// MARK: - 自动排布

enum LayoutEngine {
    /// 在屏幕可见区域内按格子扫描，找一块不与现有框重叠的位置。
    static func nextFreeFrame(size: CGSize, existing: [CGRect]) -> CGRect {
        let screen = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 22
        let cellW = size.width + gap
        let cellH = size.height + gap
        let cols = max(1, Int((screen.width - gap * 2) / cellW))

        var index = 0
        let maxCells = max(cols, 1) * 6
        while index < maxCells {
            let col = index % cols
            let row = index / cols
            let x = screen.minX + gap + CGFloat(col) * cellW
            let y = screen.maxY - gap - size.height - CGFloat(row) * cellH
            let candidate = CGRect(x: x, y: y, width: size.width, height: size.height)
            let overlaps = existing.contains { $0.intersects(candidate.insetBy(dx: -10, dy: -10)) }
            if !overlaps { return candidate }
            index += 1
        }

        // 兜底：从右上角阶梯式铺开
        let cascade = CGFloat(existing.count % 8) * 28
        return CGRect(
            x: screen.maxX - size.width - gap - cascade,
            y: screen.maxY - size.height - gap - cascade,
            width: size.width,
            height: size.height
        )
    }

    /// 保证窗口至少有一部分落在可见屏幕内。
    static func sanitize(_ frame: CGRect, minSize: CGSize = CGSize(width: 220, height: 200)) -> CGRect {
        var result = frame
        result.size.width = max(result.size.width, minSize.width)
        result.size.height = max(result.size.height, minSize.height)

        let screens = NSScreen.screens
        let visible = screens.first { $0.frame.intersects(frame) }?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let bounds = visible else { return result }

        // 完全跑出屏幕时重置到右上角
        if !bounds.intersects(result) {
            return CGRect(
                x: bounds.maxX - result.width - 24,
                y: bounds.maxY - result.height - 24,
                width: result.width,
                height: result.height
            )
        }
        // 顶部跑出去就拉回来
        if result.maxY > bounds.maxY {
            result.origin.y = bounds.maxY - result.height
        }
        if result.maxY < bounds.minY + 60 {
            result.origin.y = bounds.minY + 60
        }
        result.origin.x = min(result.origin.x, bounds.maxX - 80)
        result.origin.x = max(result.origin.x, bounds.minX - result.width + 80)
        return result
    }
}
