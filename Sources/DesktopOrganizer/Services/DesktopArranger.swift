import AppKit

/// 「整理」这件事的全部逻辑。
///
/// 新方案里，整理框**不装文件**：它只是桌面上的一块区域，文件照旧留在
/// `~/Desktop/xxx`、照旧可见。所谓"整理"就是**摆图标的坐标**。
/// 因此这里对用户文件是只读的 —— 唯一写的东西是图标位置，而那是访达自己的
/// 视图状态，不是文件内容。
enum DesktopArranger {

    /// 一个图标相对某个框的位置关系
    enum Placement {
        case inside
        case outside
        /// 从来没被手动摆过（坐标是 -1,-1），无法判断
        case unplaced
    }

    // MARK: 归属

    static func placement(of icon: DesktopIcons.Icon, in frame: CGRect) -> Placement {
        guard icon.isPlaced else { return .unplaced }
        return frame.contains(icon.position) ? .inside : .outside
    }

    /// 落在某个框区域里的图标。
    /// 多个框重叠时**返回第一个命中的**（框本该不重叠，重叠时以列表顺序为准）。
    static func icons(in frame: CGRect, from icons: [DesktopIcons.Icon]) -> [DesktopIcons.Icon] {
        icons.filter { placement(of: $0, in: frame) == .inside }
    }

    // MARK: 摆放

    /// 图标网格的尺寸（点）。和访达默认的图标间距接近。
    static let cell = CGSize(width: 100, height: 92)
    /// 框内四周留白
    static let inset: CGFloat = 20

    /// 把一个区域里能放下的位置按行优先列出来。
    static func slots(in frame: CGRect) -> [CGPoint] {
        let usable = frame.insetBy(dx: inset, dy: inset)
        let columns = max(1, Int(usable.width / cell.width))
        let rows = max(1, Int(usable.height / cell.height))
        var points: [CGPoint] = []
        for row in 0..<rows {
            for column in 0..<columns {
                points.append(CGPoint(
                    x: usable.minX + CGFloat(column) * cell.width,
                    y: usable.minY + CGFloat(row) * cell.height
                ))
            }
        }
        return points
    }

    /// 把一个框里现有的图标摆整齐（按当前名字排序，从左上开始）。
    /// 返回实际摆好的个数。
    @discardableResult
    static func tidy(_ frame: CGRect) -> Int {
        let all = DesktopIcons.readAll()
        let members = icons(in: frame, from: all)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return place(members, in: frame)
    }

    /// 把指定的一批图标摆进某个框。
    @discardableResult
    static func place(_ icons: [DesktopIcons.Icon], in frame: CGRect) -> Int {
        let points = slots(in: frame)
        var moves: [(icon: DesktopIcons.Icon, point: CGPoint)] = []
        for (index, icon) in icons.enumerated() where index < points.count {
            moves.append((icon, points[index]))
        }
        return DesktopIcons.setPositions(moves)
    }

    /// 把一批图标摆到某个框里，并**跳过**框里已经有的（用于"把选中的文件放进这个框"）。
    @discardableResult
    static func add(_ icons: [DesktopIcons.Icon], to frame: CGRect) -> Int {
        let existing = self.icons(in: frame, from: DesktopIcons.readAll())
        let existingNames = Set(existing.map(\.name))
        let newcomers = icons.filter { !existingNames.contains($0.name) }
        return place(existing + newcomers, in: frame)
    }
}
