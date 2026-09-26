import AppKit
import SwiftUI
import VehicleKit

// MARK: - MatchResultGrid：可编辑匹配结果表（M2 ParameterGrid 编辑器第一步）
//
// 编辑器形态（旧版 MatchResultTable 对齐）：
// - 有枚举字典 → NSPopUpButton 下拉（含 quickFix 推荐），值不在枚举时黄色警告
// - 手动模式 / 无枚举 → 内联 NSTextField（IME 组合态系统级保证）
// - 匹配度 → 百分比 + 三色

struct MatchResultGrid: NSViewRepresentable {
    let model: SmartFillModel
    let items: [MatchItem]

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.allowsColumnResizing = true

        for spec in Self.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.key))
            column.title = spec.title
            column.width = spec.width
            column.minWidth = 40
            column.resizingMask = [.userResizingMask]
            tableView.addTableColumn(column)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        if tableView.dataSource == nil {
            tableView.dataSource = context.coordinator
            tableView.delegate = context.coordinator
        }
        context.coordinator.model = model
        let changed = context.coordinator.items.map(\.id) != items.map(\.id)
        context.coordinator.items = items
        if changed {
            tableView.reloadData()
        } else {
            // 同一批项（手动值/枚举变更）：刷新可见单元格
            tableView.enumerateAvailableRowViews { rowView, row in
                guard row < items.count else { return }
                for (i, column) in tableView.tableColumns.enumerated() {
                    guard let view = rowView.view(atColumn: i) as? MatchCellView else { continue }
                    view.configure(item: items[row], column: column.identifier.rawValue, model: model)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, items: items)
    }

    private static let columns: [(key: String, title: String, width: CGFloat)] = [
        ("requirement", "需求参数名", 220),
        ("confidence", "匹配度", 90),
        ("matched", "匹配库参数", 240),
        ("value", "填报值 (可修正)", 330),
        ("status", "状态", 70),
    ]

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: SmartFillModel
        var items: [MatchItem]

        init(model: SmartFillModel, items: [MatchItem]) {
            self.model = model
            self.items = items
        }

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let key = tableColumn?.identifier.rawValue else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("match-cell-\(key)")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? MatchCellView)
                ?? MatchCellView()
            cell.identifier = identifier
            cell.configure(item: items[row], column: key, model: model)
            return cell
        }
    }
}

/// 单元格容器：按列配置内容（复用时重置）
final class MatchCellView: NSView {
    private let stack = NSStackView()
    private let label = NSTextField(labelWithString: "")
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let textField = NSTextField(frame: .zero)
    private let warningIcon = NSImageView()
    private let toggleButton = NSButton(title: "", target: nil, action: nil)

    private var item: MatchItem?
    private var columnKey: String?
    private var model: SmartFillModel?
    private var isManualMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.font = .systemFont(ofSize: 12)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        popup.font = .systemFont(ofSize: 11)
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.target = self
        popup.action = #selector(popupChanged)

        textField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.placeholderString = "输入填报值"
        textField.delegate = self
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.target = self
        textField.action = #selector(textCommitted)

        warningIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "枚举异常")
        warningIcon.contentTintColor = .systemOrange
        warningIcon.setContentHuggingPriority(.required, for: .horizontal)

        toggleButton.isBordered = false
        toggleButton.imagePosition = .imageOnly
        toggleButton.controlSize = .small
        toggleButton.setContentHuggingPriority(.required, for: .horizontal)
        toggleButton.target = self
        toggleButton.action = #selector(toggleMode)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    func configure(item: MatchItem, column: String, model: SmartFillModel) {
        self.item = item
        self.columnKey = column
        self.model = model

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        switch column {
        case "requirement":
            label.stringValue = item.requirementName
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            stack.addArrangedSubview(label)
        case "confidence":
            let percent = Int((item.confidence * 100).rounded())
            label.stringValue = "\(percent)%"
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = Self.confidenceColor(item.confidence)
            stack.addArrangedSubview(label)
        case "matched":
            if let matched = item.matchedParam {
                label.stringValue = matched.name
                label.textColor = .labelColor
                label.toolTip = "\(matched.group) / \(matched.name)：\(matched.displayValue)"
            } else {
                label.stringValue = "未匹配"
                label.textColor = .systemRed
                label.toolTip = nil
            }
            stack.addArrangedSubview(label)
        case "value":
            configureValueCell(item: item, model: model)
        case "status":
            let text = item.manualValue != nil ? "手动" : (item.matchedParam != nil ? "已匹配" : "未匹配")
            label.stringValue = text
            label.textColor = item.manualValue != nil ? .controlAccentColor : .secondaryLabelColor
            stack.addArrangedSubview(label)
        default:
            break
        }
    }

    private func configureValueCell(item: MatchItem, model: SmartFillModel) {
        let enumValues = model.enumDictionary.enumValues(for: item.requirementName)
        let hasEnums = !enumValues.isEmpty
        let currentValue = item.effectiveValue
        // 手动模式：用户显式改过值且值不在枚举内（改到枚举内的值自动回到枚举形态）
        isManualMode = hasEnums && item.manualValue != nil && !enumValues.contains(item.manualValue!)

        if isManualMode || !hasEnums {
            // 手动文本模式
            textField.stringValue = item.manualValue ?? currentValue
            if hasEnums {
                textField.placeholderString = "手动输入（枚举外）"
                textField.textColor = .systemOrange
            } else {
                textField.placeholderString = "输入填报值"
                textField.textColor = .labelColor
            }
            stack.addArrangedSubview(textField)
            if hasEnums {
                configureToggleButton()
                stack.addArrangedSubview(toggleButton)
            }
        } else {
            // 枚举下拉模式（含 quickFix 推荐，完整值存 representedObject）
            popup.removeAllItems()
            if currentValue.isEmpty {
                let placeholder = NSMenuItem(title: "选择填报值", action: nil, keyEquivalent: "")
                popup.menu?.addItem(placeholder)
            }
            for v in enumValues {
                let menuItem = NSMenuItem(title: v.count > 40 ? String(v.prefix(40)) + "…" : v, action: nil, keyEquivalent: "")
                menuItem.representedObject = v
                popup.menu?.addItem(menuItem)
            }
            let fixes = model.quickFixes(for: item)
            let fixValues = fixes.map(\.value).filter { !enumValues.contains($0) && $0 != currentValue }
            if !fixValues.isEmpty {
                popup.menu?.addItem(.separator())
                for fix in fixValues {
                    let menuItem = NSMenuItem(title: "推荐：" + (fix.count > 20 ? String(fix.prefix(20)) + "…" : fix),
                                              action: nil, keyEquivalent: "")
                    menuItem.representedObject = fix
                    popup.menu?.addItem(menuItem)
                }
            }
            if !currentValue.isEmpty {
                popup.selectItem(withTitle: currentValue)
                if popup.selectedItem == nil {
                    // 当前值不在枚举/推荐内 → 追加为异常项展示
                    let item2 = NSMenuItem(title: currentValue, action: nil, keyEquivalent: "")
                    item2.representedObject = currentValue
                    popup.menu?.addItem(item2)
                    popup.select(popup.item(withTitle: currentValue))
                }
            }
            popup.toolTip = currentValue.isEmpty ? enumValues.prefix(8).joined(separator: " / ") : currentValue
            stack.addArrangedSubview(popup)
            configureToggleButton()
            stack.addArrangedSubview(toggleButton)
        }

        if model.isEnumMismatch(item) {
            warningIcon.toolTip = "“\(currentValue)”不在枚举列表中，需更新字典"
            stack.addArrangedSubview(warningIcon)
        }
    }

    private func configureToggleButton() {
        toggleButton.image = NSImage(systemSymbolName: "pencil.and.list.clipboard",
                                     accessibilityDescription: "切换输入模式")
        toggleButton.toolTip = "切换为手动输入 / 枚举选择"
    }

    @objc private func popupChanged() {
        guard let item, let model,
              let selected = popup.selectedItem,
              let fullValue = selected.representedObject as? String else { return }
        model.updateManualValue(id: item.id, fullValue)
    }

    @objc private func textCommitted() {
        commitText()
    }

    @objc private func toggleMode() {
        guard let item, let model else { return }
        if isManualMode {
            // 切回枚举模式：撤销手动值
            model.updateManualValue(id: item.id, nil)
        } else {
            // 切到手动模式：固化当前值（含显式空值，不回退自动值）
            model.updateManualValue(id: item.id, item.effectiveValue)
        }
        // @Observable 触发 updateNSView → 重配可见单元格
    }

    private func commitText() {
        guard let item, let model else { return }
        model.updateManualValue(id: item.id, textField.stringValue)
    }

    static func confidenceColor(_ confidence: Double) -> NSColor {
        confidence > 0.8 ? .systemGreen : (confidence > 0.5 ? .systemOrange : .systemRed)
    }
}

extension MatchCellView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }
}
