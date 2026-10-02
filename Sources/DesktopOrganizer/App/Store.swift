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

// MARK: - 引用项

/// 整理框里的一个条目。**只记录路径，永远不搬运文件。**
struct BoxItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var path: String
    var addedAt: Date = Date()
    /// 是不是「我们」把它从原位置隐藏起来的。
    /// 只恢复自己动过的文件，绝不碰用户手动隐藏的东西。
    var didHide: Bool = false

    init(path: String) {
        self.path = path
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        path = c.value(.path, "")
        addedAt = c.value(.addedAt, Date())
        didHide = c.value(.didHide, false)
    }

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

// MARK: - 整理框

struct BoxConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "新建整理框"
    var items: [BoxItem] = []
    var frameX: Double = 0
    var frameY: Double = 0
    var frameW: Double = 300
    var frameH: Double = 360
    var opacity: Double = 0.8
    var material: BoxMaterial = .hud
    var cornerRadius: Double = 20
    var floatOnTop: Bool = false
    var accentHex: String = "0A84FF"
    /// 1.0 用它记录「搬移目标文件夹」。现在只用于一次性迁移，之后不再有任何搬移行为。
    var legacyFolderPath: String? = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, name, items, frameX, frameY, frameW, frameH
        case opacity, material, cornerRadius, floatOnTop, accentHex
        case legacyFolderPath
        case folderPath          // 1.0 的字段名，仅解码
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "整理框")
        items = c.value(.items, [])
        frameX = c.value(.frameX, 0)
        frameY = c.value(.frameY, 0)
        frameW = c.value(.frameW, 300)
        frameH = c.value(.frameH, 360)
        opacity = c.value(.opacity, 0.8)
        material = c.value(.material, .hud)
        cornerRadius = c.value(.cornerRadius, 20)
        floatOnTop = c.value(.floatOnTop, false)
        accentHex = c.value(.accentHex, "0A84FF")
        legacyFolderPath = ((try? c.decodeIfPresent(String.self, forKey: .legacyFolderPath)) ?? nil)
            ?? ((try? c.decodeIfPresent(String.self, forKey: .folderPath)) ?? nil)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(items, forKey: .items)
        try c.encode(frameX, forKey: .frameX)
        try c.encode(frameY, forKey: .frameY)
        try c.encode(frameW, forKey: .frameW)
        try c.encode(frameH, forKey: .frameH)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(material, forKey: .material)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(floatOnTop, forKey: .floatOnTop)
        try c.encode(accentHex, forKey: .accentHex)
    }

    /// 引用已经失效（文件被移走或删掉）的条目数。
    /// 主窗口卡片和整理框内容都用它，避免同一个事实两处各算一遍。
    var missingItemCount: Int {
        items.reduce(0) { $0 + ($1.exists ? 0 : 1) }
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

    /// 不允许被收进整理框的路径：程序自己，以及桌面根目录本身。
    static func isProtected(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        let app = Bundle.main.bundleURL.standardizedFileURL.path
        if target == app || app.hasPrefix(target + "/") { return true }
        if target == AppPaths.desktopDirectory.standardizedFileURL.path { return true }
        return false
    }
}

// MARK: - 全局偏好

struct Preferences: Codable, Equatable {
    var defaultOpacity: Double = 0.8
    var defaultMaterial: BoxMaterial = .hud
    var defaultCornerRadius: Double = 20
    var defaultFloatOnTop: Bool = false
    var confirmBeforeCategorize: Bool = true
    var showMenuBarIcon: Bool = true
    var openMainWindowOnLaunch: Bool = true
    /// 装进「应用程序」后自动清掉安装包
    var removeInstallerAfterInstall: Bool = true
    /// 一次性开关，避免以后把新下载的安装包也删掉
    var didRunInstallerCleanup: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultOpacity = c.value(.defaultOpacity, 0.8)
        defaultMaterial = c.value(.defaultMaterial, .hud)
        defaultCornerRadius = c.value(.defaultCornerRadius, 20)
        defaultFloatOnTop = c.value(.defaultFloatOnTop, false)
        confirmBeforeCategorize = c.value(.confirmBeforeCategorize, true)
        showMenuBarIcon = c.value(.showMenuBarIcon, true)
        openMainWindowOnLaunch = c.value(.openMainWindowOnLaunch, true)
        removeInstallerAfterInstall = c.value(.removeInstallerAfterInstall, true)
        didRunInstallerCleanup = c.value(.didRunInstallerCleanup, false)
    }
}

// MARK: - 落盘结构

/// 配置格式版本。save() 和迁移判断必须用同一个值，
/// 否则写回去的还是旧版本号，迁移会在每次启动时重跑 —— 用户就永远打不开置顶了。
private let kConfigVersion = 3

private struct AppConfig: Codable {
    var version: Int = kConfigVersion
    var boxes: [BoxConfig] = []
    var prefs: Preferences = Preferences()
    /// 本程序隐藏过的路径。跟整理框解耦，见 Store.hiddenPaths 的说明。
    var hiddenPaths: [String] = []

    /// 必须宽容解码。
    ///
    /// Swift 合成的 init(from:) 对**非可选**属性一律要求键存在，即使它有默认值 ——
    /// 给这个结构加字段时，旧配置会因为缺键整份解码失败。load() 用的又是 try?，
    /// 失败会静默变成空配置，紧接着 save() 把空配置写回去 —— 用户的整理框就被清空了。
    /// 这个坑真的发生过一次。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, kConfigVersion)
        boxes = c.value(.boxes, [])
        prefs = c.value(.prefs, Preferences())
        hiddenPaths = c.value(.hiddenPaths, [])
    }

    init() {}

    init(version: Int, boxes: [BoxConfig], prefs: Preferences, hiddenPaths: [String]) {
        self.version = version
        self.boxes = boxes
        self.prefs = prefs
        self.hiddenPaths = hiddenPaths
    }
}

// MARK: - Store

final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var boxes: [BoxConfig] = []
    @Published var prefs: Preferences = Preferences() {
        didSet { scheduleSave() }
    }

    /// 本程序隐藏过的路径。
    ///
    /// 刻意与整理框解耦：同一个文件可以被多个整理框引用，若只靠条目上的 didHide
    /// 判断，第二个框加入时该文件已经是隐藏状态、不会被认领，于是最后一个框移除它
    /// 时谁都不负责恢复 —— 文件就永久隐藏了。
    private(set) var hiddenPaths: Set<String> = []

    /// 无头自检模式（--selftest 等）禁止写盘。
    /// 那些模式会大量改动 Store，而保存是 0.6 秒防抖的 —— 一旦测试跑得稍慢，
    /// 防抖就会真的把测试用的临时状态写进用户的真实配置。
    var persistenceSuppressed = false

    private var saveWorkItem: DispatchWorkItem?
    private var isLoading = false

    private init() {}

    // MARK: 读写

    func load() {
        isLoading = true
        defer { isLoading = false }

        let hadConfig = FileManager.default.fileExists(atPath: AppPaths.configURL.path)
        if let data = try? Data(contentsOf: AppPaths.configURL),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            boxes = config.boxes
            prefs = config.prefs
            hiddenPaths = Set(config.hiddenPaths)
            migrateLegacyFolders()
            migrateHiddenPaths()
            migrateToDesktopLayer(from: config.version)
        }

        if boxes.isEmpty && !hadConfig {
            createStarterBoxes()
        }
        save()
    }

    /// 老配置只有条目级的 didHide。把它汇总成 hiddenPaths，之后由 hiddenPaths 说了算。
    private func migrateHiddenPaths() {
        guard hiddenPaths.isEmpty else { return }
        for box in boxes {
            for item in box.items where item.didHide {
                hiddenPaths.insert(item.path)
            }
        }
    }

    /// v3 起整理框默认贴在桌面层（在应用窗口下面），而不是浮在所有窗口之上。
    /// 老配置里的窗口一次性落到桌面层，用户可以逐个再打开置顶。
    private func migrateToDesktopLayer(from version: Int) {
        guard version < kConfigVersion else { return }
        for index in boxes.indices {
            boxes[index].floatOnTop = false
        }
        prefs.defaultFloatOnTop = false
    }

    /// 1.0 的整理框绑定「搬移目标文件夹」。升级后把该文件夹里已有的内容导入成**引用**，
    /// 只读不改，一次性完成；之后这个字段彻底弃用，程序再也不会移动任何文件。
    private func migrateLegacyFolders() {
        for index in boxes.indices {
            guard let folderPath = boxes[index].legacyFolderPath, !folderPath.isEmpty else { continue }
            boxes[index].legacyFolderPath = nil
            guard boxes[index].items.isEmpty else { continue }
            let folder = URL(fileURLWithPath: folderPath)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                boxes[index].items.append(BoxItem(path: folder.appendingPathComponent(name).path))
            }
        }
    }

    func save() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let config = AppConfig(version: kConfigVersion, boxes: boxes, prefs: prefs,
                               hiddenPaths: Array(hiddenPaths).sorted())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: AppPaths.configURL, options: .atomic)
    }

    private func scheduleSave() {
        guard !isLoading, !persistenceSuppressed else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    // MARK: 查询

    func box(id: UUID) -> BoxConfig? {
        boxes.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        boxes.firstIndex { $0.id == id }
    }

    func itemCount(of id: UUID) -> Int {
        box(id: id)?.items.count ?? 0
    }

    // MARK: 增删改

    func update(id: UUID, _ mutate: (inout BoxConfig) -> Void) {
        guard let index = index(of: id) else { return }
        mutate(&boxes[index])
        scheduleSave()
    }

    @discardableResult
    func addBox(name: String? = nil, items: [BoxItem] = [], frame: CGRect? = nil) -> BoxConfig {
        var box = BoxConfig()
        box.name = name ?? "整理框 \(boxes.count + 1)"
        box.items = items
        box.opacity = prefs.defaultOpacity
        box.material = prefs.defaultMaterial
        box.cornerRadius = prefs.defaultCornerRadius
        box.floatOnTop = prefs.defaultFloatOnTop
        box.accentHex = AccentPalette.all[boxes.count % AccentPalette.all.count]

        let size = CGSize(width: 300, height: 360)
        box.frame = frame ?? LayoutEngine.nextFreeFrame(size: size, existing: boxes.map(\.frame))

        boxes.append(box)
        scheduleSave()
        return box
    }

    func removeBox(id: UUID) {
        guard let index = index(of: id) else { return }
        let removed = boxes[index].items
        boxes.remove(at: index)
        restoreVisibility(of: removed)
        scheduleSave()
    }

    /// 往框里加条目。进框的同时把原位置隐藏起来（路径不变）。
    /// 已在框内或受保护的路径会跳过，返回真正新增的数量。
    @discardableResult
    func addItems(_ urls: [URL], to id: UUID, at position: Int? = nil) -> Int {
        guard let boxIndex = index(of: id) else { return 0 }
        var known = Set(boxes[boxIndex].items.map(\.path))
        var fresh: [BoxItem] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            guard !path.isEmpty, !known.contains(path), !BoxConfig.isProtected(url) else { continue }

            var item = BoxItem(path: path)
            if HiddenFlag.isHidden(url) {
                // 已经是隐藏状态：可能是我们之前隐藏的（另一个框引用过），
                // 也可能是用户自己隐藏的。交给 hiddenPaths 去记，不在这里下结论。
                item.didHide = hiddenPaths.contains(path)
            } else if HiddenFlag.setHidden(true, for: url) {
                item.didHide = true
                hiddenPaths.insert(path)
            }
            fresh.append(item)
            known.insert(path)
        }

        guard !fresh.isEmpty else { return 0 }
        if let position {
            let at = max(0, min(position, boxes[boxIndex].items.count))
            boxes[boxIndex].items.insert(contentsOf: fresh, at: at)
        } else {
            boxes[boxIndex].items.append(contentsOf: fresh)
        }
        scheduleSave()
        return fresh.count
    }

    @discardableResult
    func removeItems(_ itemIDs: Set<UUID>, from id: UUID) -> Int {
        guard let index = index(of: id) else { return 0 }
        let removed = boxes[index].items.filter { itemIDs.contains($0.id) }
        guard !removed.isEmpty else { return 0 }
        boxes[index].items.removeAll { itemIDs.contains($0.id) }
        restoreVisibility(of: removed)
        scheduleSave()
        return removed.count
    }

    func removeAllItems(from id: UUID) {
        guard let index = index(of: id) else { return }
        let removed = boxes[index].items
        guard !removed.isEmpty else { return }
        boxes[index].items.removeAll()
        restoreVisibility(of: removed)
        scheduleSave()
    }

    /// 恢复原位置显示。只处理我们隐藏过的，且只有当没有任何整理框还引用它时才恢复。
    /// 恢复原位置显示。判据是 hiddenPaths（我们确实隐藏过），
    /// 并且此刻已经没有任何整理框还引用它。
    private func restoreVisibility(of items: [BoxItem]) {
        for item in items {
            let path = item.path
            guard hiddenPaths.contains(path) else { continue }
            let stillReferenced = boxes.contains { box in
                box.items.contains { $0.path == path }
            }
            guard !stillReferenced else { continue }
            HiddenFlag.setHidden(false, for: item.url)
            hiddenPaths.remove(path)
        }
    }

    /// 兜底：把本程序隐藏过的文件全部恢复显示。
    @discardableResult
    func restoreAllHidden() -> Int {
        var count = 0
        for path in hiddenPaths {
            if HiddenFlag.setHidden(false, for: URL(fileURLWithPath: path)) { count += 1 }
        }
        hiddenPaths.removeAll()
        for boxIndex in boxes.indices {
            for itemIndex in boxes[boxIndex].items.indices {
                boxes[boxIndex].items[itemIndex].didHide = false
            }
        }
        if count > 0 { scheduleSave() }
        return count
    }

    /// 当前被本程序隐藏着的文件数（与整理框数量无关）。
    var hiddenItemCount: Int { hiddenPaths.count }

    // MARK: 拖拽

    /// 框内重排（支持多选一次挪动）。
    func moveItems(in boxID: UUID, itemIDs: [UUID], to targetIndex: Int) {
        guard let boxIndex = index(of: boxID) else { return }
        let movingIDs = Set(itemIDs)
        let moving = boxes[boxIndex].items.filter { movingIDs.contains($0.id) }
        guard !moving.isEmpty else { return }

        boxes[boxIndex].items.removeAll { movingIDs.contains($0.id) }
        let to = max(0, min(targetIndex, boxes[boxIndex].items.count))
        boxes[boxIndex].items.insert(contentsOf: moving, at: to)
        scheduleSave()
    }

    /// 把条目从一个整理框拖到另一个整理框。didHide 状态跟着走，不重复动文件。
    @discardableResult
    func transferItems(_ itemIDs: [UUID], from sourceBox: UUID, to targetBox: UUID, at targetIndex: Int) -> Bool {
        guard sourceBox != targetBox,
              let sourceIndex = index(of: sourceBox),
              let targetBoxIndex = index(of: targetBox) else { return false }
        let movingIDs = Set(itemIDs)
        let moving = boxes[sourceIndex].items.filter { movingIDs.contains($0.id) }
        guard !moving.isEmpty else { return false }

        boxes[sourceIndex].items.removeAll { movingIDs.contains($0.id) }
        let to = max(0, min(targetIndex, boxes[targetBoxIndex].items.count))
        boxes[targetBoxIndex].items.insert(contentsOf: moving, at: to)
        scheduleSave()
        return true
    }

    /// 单个条目的原位置显示/隐藏切换。
    func setItemHidden(_ hidden: Bool, itemID: UUID, in boxID: UUID) {
        guard let boxIndex = index(of: boxID),
              let itemIndex = boxes[boxIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        let url = boxes[boxIndex].items[itemIndex].url
        guard HiddenFlag.setHidden(hidden, for: url) else { return }
        if hidden {
            hiddenPaths.insert(url.standardizedFileURL.path)
        } else {
            hiddenPaths.remove(url.standardizedFileURL.path)
        }
        boxes[boxIndex].items[itemIndex].didHide = hidden
        scheduleSave()
    }

    /// 按路径改隐藏状态。用于「在访达中显示」这类只有 URL、没有条目 ID 的场景。
    func setPathHidden(_ hidden: Bool, path: String) {
        let url = URL(fileURLWithPath: path)
        guard HiddenFlag.setHidden(hidden, for: url) else { return }
        let key = url.standardizedFileURL.path
        if hidden { hiddenPaths.insert(key) } else { hiddenPaths.remove(key) }
        for boxIndex in boxes.indices {
            for itemIndex in boxes[boxIndex].items.indices where boxes[boxIndex].items[itemIndex].path == path {
                boxes[boxIndex].items[itemIndex].didHide = hidden
            }
        }
        scheduleSave()
    }

    func isItemHidden(_ itemID: UUID, in boxID: UUID) -> Bool {
        guard let box = box(id: boxID),
              let item = box.items.first(where: { $0.id == itemID }) else { return false }
        return HiddenFlag.isHidden(item.url)
    }

    // MARK: 首次启动

    private func createStarterBoxes() {
        for name in ["待整理", "图片", "文档"] {
            addBox(name: name)
        }
        save()
    }
}

// MARK: - 自动排布

enum LayoutEngine {
    /// 从右上角开始扫，避开已有窗口 —— 不再往左上角堆。
    static func nextFreeFrame(size: CGSize, existing: [CGRect]) -> CGRect {
        let screen = NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let gap: CGFloat = 22
        let cellW = size.width + gap
        let cellH = size.height + gap
        let cols = max(1, Int((screen.width - gap * 2) / cellW))

        var index = 0
        while index < cols * 6 {
            let col = index % cols
            let row = index / cols
            let x = screen.maxX - gap - size.width - CGFloat(col) * cellW
            let y = screen.maxY - gap - size.height - CGFloat(row) * cellH
            let candidate = CGRect(x: x, y: y, width: size.width, height: size.height)
            if !existing.contains(where: { $0.intersects(candidate.insetBy(dx: -10, dy: -10)) }) {
                return candidate
            }
            index += 1
        }

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

        let visible = NSScreen.screens.first { $0.frame.intersects(frame) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let bounds = visible else { return result }

        if !bounds.intersects(result) {
            return CGRect(x: bounds.maxX - result.width - 24,
                          y: bounds.maxY - result.height - 24,
                          width: result.width, height: result.height)
        }
        if result.maxY > bounds.maxY { result.origin.y = bounds.maxY - result.height }
        if result.maxY < bounds.minY + 60 { result.origin.y = bounds.minY + 60 }
        result.origin.x = min(result.origin.x, bounds.maxX - 80)
        result.origin.x = max(result.origin.x, bounds.minX - result.width + 80)
        return result
    }
}
