import AppKit
import Observation
import VehicleKit

// MARK: - diff 行模型（ParameterGrid 的展示单元）

struct DiffRow: Identifiable, Hashable {
    enum State: String, CaseIterable {
        case added = "新增"
        case removed = "删除"
        case modified = "修改"
        case unchanged = "未变"

        var ranking: Int {
            switch self {
            case .modified: 0
            case .added: 1
            case .removed: 2
            case .unchanged: 3
            }
        }
    }

    let id: String
    let state: State
    let group: String
    let name: String
    let oldValue: String
    let newValue: String
    let productName: String?
}

enum DiffFilter: String, CaseIterable {
    case all = "全部"
    case added = "新增"
    case removed = "删除"
    case modified = "修改"
    case unchanged = "未变"
}

// MARK: - Workbench 视图模型

@MainActor
@Observable
final class WorkbenchModel {
    var baseFileURL: URL?
    var targetFileURL: URL?
    var mode: CompareMode = .content
    var filter: DiffFilter = .all

    private(set) var baseSheet: SheetData?
    private(set) var targetSheet: SheetData?
    private(set) var diff: DiffResult?

    private(set) var baseSummary: String?
    private(set) var targetSummary: String?
    private(set) var lastError: String?
    private(set) var isComparing = false

    var rows: [DiffRow] {
        guard let diff else { return [] }
        var result: [DiffRow] = []

        func shouldInclude(_ state: DiffRow.State) -> Bool {
            filter == .all || DiffFilter(rawValue: state.rawValue) == filter
        }

        if shouldInclude(.modified) {
            result.append(contentsOf: diff.modified.map { m in
                DiffRow(
                    id: "m-\(m.id)-\(m.oldParam.productName ?? "")",
                    state: .modified,
                    group: m.oldParam.group,
                    name: m.oldParam.name,
                    oldValue: m.oldParam.displayValue,
                    newValue: m.newParam.displayValue,
                    productName: m.oldParam.productName
                )
            })
        }
        if shouldInclude(.added) {
            result.append(contentsOf: diff.added.map { p in
                DiffRow(id: "a-\(p.id)", state: .added, group: p.group, name: p.name,
                        oldValue: "", newValue: p.displayValue, productName: p.productName)
            })
        }
        if shouldInclude(.removed) {
            result.append(contentsOf: diff.removed.map { p in
                DiffRow(id: "r-\(p.id)", state: .removed, group: p.group, name: p.name,
                        oldValue: p.displayValue, newValue: "", productName: p.productName)
            })
        }
        if shouldInclude(.unchanged) {
            result.append(contentsOf: diff.unchanged.map { p in
                DiffRow(id: "u-\(p.id)", state: .unchanged, group: p.group, name: p.name,
                        oldValue: p.displayValue, newValue: p.displayValue, productName: p.productName)
            })
        }
        // 修改优先，其余按原归类顺序
        return result.sorted { $0.state.ranking < $1.state.ranking }
    }

    var countsText: String {
        guard let diff else { return "" }
        return "新增 \(diff.added.count) · 删除 \(diff.removed.count) · 修改 \(diff.modified.count) · 未变 \(diff.unchanged.count)"
    }

    var canExportPDF: Bool { !rows.isEmpty }

    func clearError() {
        lastError = nil
    }

    // MARK: 文件选择与解析

    func chooseBaseFile() {
        chooseXlsx { url in
            self.baseFileURL = url
            self.parse(url: url) { sheet, summary, error in
                self.baseSheet = sheet
                self.baseSummary = summary
                if error != nil { self.lastError = error }
                self.runCompareIfNeeded()
            }
        }
    }

    func chooseTargetFile() {
        chooseXlsx { url in
            self.targetFileURL = url
            self.parse(url: url) { sheet, summary, error in
                self.targetSheet = sheet
                self.targetSummary = summary
                if error != nil { self.lastError = error }
                self.runCompareIfNeeded()
            }
        }
    }

    private func chooseXlsx(_ completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func parse(
        url: URL, completion: @escaping (SheetData?, String?, String?) -> Void
    ) {
        lastError = nil
        isComparing = true
        Task {
            do {
                let sheet = try await Task.detached(priority: .userInitiated) {
                    try ExcelParser.parse(url: url)
                }.value
                let summary = "\(sheet.data.count) 参数 · \(Set(sheet.data.compactMap(\.productName)).count) 产品 · \(Set(sheet.data.compactMap(\.originSheet)).count) Sheet"
                completion(sheet, summary, nil)
            } catch {
                let message: String
                if let parseError = error as? ParseError {
                    message = "\(url.lastPathComponent)：\(parseError.message)\n\(parseError.diagnostics.suggestion)"
                } else {
                    message = "\(url.lastPathComponent)：\(error.localizedDescription)"
                }
                completion(nil, nil, message)
            }
            runCompareIfNeeded()
        }
    }

    private func runCompareIfNeeded() {
        guard baseSheet != nil, targetSheet != nil, !isComparing else { return }
        guard let base = baseSheet, let target = targetSheet else { return }
        diff = compareSheets(base, target, mode: mode)
        isComparing = false
    }

    func modeChanged() {
        guard baseSheet != nil, targetSheet != nil else { return }
        diff = compareSheets(baseSheet!, targetSheet!, mode: mode)
    }

    // MARK: PDF 导出

    func exportPDF() {
        guard !rows.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "参数对比报告.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiffReportPDFWriter.write(
                rows: rows,
                baseName: baseFileURL?.lastPathComponent ?? "基准文件",
                targetName: targetFileURL?.lastPathComponent ?? "对比文件",
                countsText: countsText,
                modeText: mode == .miit ? "公告对比" : "内容对比",
                to: url
            )
        } catch {
            lastError = "PDF 导出失败：\(error.localizedDescription)"
        }
    }
}
