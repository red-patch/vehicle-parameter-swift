import AppKit
import SwiftUI

// MARK: - ParameterGrid：NSTableView 封装（核心表格组件）
//
// M1 形态：只读 diff 四态着色（行背景 + 左侧色条），视图复用保证大表滚动满帧。
// M2 起按 枚举下拉 → 文本 → 修复入口 渐进上线单元格编辑器。

/// diff 四态配色（与旧版 DiffViewer 的语义对应）
enum DiffRowStyle {
    case added, removed, modified, unchanged

    var barColor: NSColor {
        switch self {
        case .added: .systemGreen
        case .removed: .systemRed
        case .modified: .systemOrange
        case .unchanged: .systemGray.withAlphaComponent(0.4)
        }
    }

    /// 行背景（浅色，不干扰正文）
    var background: NSColor {
        switch self {
        case .added: .systemGreen.withAlphaComponent(0.10)
        case .removed: .systemRed.withAlphaComponent(0.10)
        case .modified: .systemOrange.withAlphaComponent(0.14)
        case .unchanged: .controlBackgroundColor
        }
    }
}

/// 带左侧色条的行视图
final class DiffTableRowView: NSTableRowView {
    var style: DiffRowStyle = .unchanged {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        style.background.setFill()
        bounds.fill()
        // 左侧 3pt 状态色条
        let bar = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 3, height: bounds.height))
        style.barColor.setFill()
        bar.fill()
        super.draw(dirtyRect)
    }
}

struct ParameterGrid: NSViewRepresentable {
    let rows: [DiffRow]

    static let columnKeys = ["state", "group", "name", "old", "new", "product"]
    private static let columnTitles = ["状态", "分组", "参数名", "基准值", "对比值", "产品"]
    private static let columnWidths: [CGFloat] = [52, 130, 190, 140, 140, 150]

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 26
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .controlBackgroundColor
        tableView.usesAutomaticRowHeights = false
        tableView.allowsColumnResizing = true
        tableView.doubleAction = nil

        for (i, key) in Self.columnKeys.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = Self.columnTitles[i]
            column.width = Self.columnWidths[i]
            column.minWidth = 40
            column.resizingMask = [.userResizingMask, .autoresizingMask]
            tableView.addTableColumn(column)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        if tableView.delegate == nil {
            tableView.dataSource = context.coordinator
            tableView.delegate = context.coordinator
        }
        context.coordinator.rows = rows
        // M1 规模（千行级）reloadData 足够；万行级滚动时再引入增量更新
        tableView.reloadData()
        tableView.backgroundColor = .controlBackgroundColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rows: rows)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var rows: [DiffRow]

        init(rows: [DiffRow]) {
            self.rows = rows
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("diff-row")
            let view = (tableView.makeView(withIdentifier: identifier, owner: nil) as? DiffTableRowView)
                ?? DiffTableRowView()
            view.identifier = identifier
            switch rows[row].state {
            case .added: view.style = .added
            case .removed: view.style = .removed
            case .modified: view.style = .modified
            case .unchanged: view.style = .unchanged
            }
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let key = tableColumn?.identifier.rawValue else { return nil }
            let item = rows[row]

            let identifier = NSUserInterfaceItemIdentifier("cell-\(key)")
            let field = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField)
                ?? NSTextField(labelWithString: "")
            field.identifier = identifier
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.font = .systemFont(ofSize: 12, weight: key == "state" ? .semibold : .regular)

            switch key {
            case "state":
                field.stringValue = item.state.rawValue
                field.textColor = NSColor.labelColor.withAlphaComponent(0.75)
            case "group":
                field.stringValue = item.group
                field.textColor = .secondaryLabelColor
            case "name":
                field.stringValue = item.name
            case "old":
                field.stringValue = item.oldValue
            case "new":
                field.stringValue = item.newValue
            case "product":
                field.stringValue = item.productName ?? ""
                field.textColor = .secondaryLabelColor
            default:
                field.stringValue = ""
            }
            // 修改态的两侧值用强调色，突出变化
            if item.state == .modified, key == "old" || key == "new" {
                field.textColor = .controlAccentColor
                field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            }
            return field
        }
    }
}

#Preview("四态") {
    let sample: [DiffRow] = [
        .init(id: "1", state: .modified, group: "车身", name: "整备质量(kg)",
              oldValue: "1780", newValue: "1820", productName: "DNC5037"),
        .init(id: "2", state: .added, group: "动力", name: "充电效率",
              oldValue: "", newValue: "95%", productName: "DNC5037"),
        .init(id: "3", state: .removed, group: "底盘", name: "钢板弹簧片数",
              oldValue: "3", newValue: "", productName: "DNC5037"),
        .init(id: "4", state: .unchanged, group: "车身", name: "轴距(mm)",
              oldValue: "2900", newValue: "2900", productName: "DNC5037"),
    ]
    return ParameterGrid(rows: sample)
        .frame(width: 720, height: 180)
}
