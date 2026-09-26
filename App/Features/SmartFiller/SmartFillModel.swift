import AppKit
import Observation
import VehicleKit

// MARK: - SmartFiller 视图模型（旧版 SmartFillView + MatchResultTable 域侧状态）

@MainActor
@Observable
final class SmartFillModel {
    // MARK: 输入

    var requirementsText = ""
    var libraryFileURL: URL?
    var selectedProduct: String?

    // MARK: 数据

    private(set) var librarySheet: SheetData?
    private(set) var libraryProducts: [ProductConfidence] = []
    private(set) var items: [MatchItem] = []
    private(set) var librarySummary: String?
    private(set) var lastError: String?

    /// 枚举字典（内置 CSV，启动加载）
    let enumDictionary = EnumDictionary.loadBundled()

    /// 需求文本变化去抖计时器（旧版 500ms 输入即触发）
    private var debounceTask: Task<Void, Never>?

    init() {
        if let libraryFileURL {
            parseLibrary(url: libraryFileURL)
        }
    }

    // MARK: 基准库

    func chooseLibraryFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryFileURL = url
        parseLibrary(url: url)
    }

    private func parseLibrary(url: URL) {
        lastError = nil
        items = []
        Task {
            do {
                let sheet = try await Task.detached(priority: .userInitiated) {
                    try ExcelParser.parse(url: url)
                }.value
                // 产品参数计数 → 置信度评估排序
                var counts: [String: Int] = [:]
                for p in sheet.data {
                    counts[p.productName ?? "", default: 0] += 1
                }
                let products = ProductConfidenceEvaluator.evaluateAll(
                    counts.map { (name: $0.key, paramCount: $0.value) })
                librarySheet = sheet
                libraryProducts = products
                librarySummary = "\(sheet.data.count) 参数 · \(products.count) 产品"
                // 默认选最高置信度产品
                selectedProduct = products.first?.name
            } catch {
                let message: String
                if let parseError = error as? ParseError {
                    message = "\(url.lastPathComponent)：\(parseError.message)\n\(parseError.diagnostics.suggestion)"
                } else {
                    message = "\(url.lastPathComponent)：\(error.localizedDescription)"
                }
                lastError = message
                librarySheet = nil
                libraryProducts = []
                selectedProduct = nil
            }
        }
    }

    /// 当前产品的参数库
    var library: [VehicleParameter] {
        guard let librarySheet, let selectedProduct else { return [] }
        return librarySheet.data.filter { $0.productName == selectedProduct }
    }

    func productChanged() {
        if !requirementsText.isEmpty {
            runMatch()
        }
    }

    // MARK: 匹配（输入即触发，500ms 去抖）

    func requirementsTextChanged() {
        debounceTask?.cancel()
        guard !requirementsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !library.isEmpty else {
            items = []
            return
        }
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            runMatch()
        }
    }

    private func runMatch() {
        items = SmartFiller.match(requirementsText: requirementsText, library: library)
    }

    // MARK: 手动值 / 枚举 / quickFix

    func updateManualValue(id: String, _ value: String?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx] = SmartFiller.updateManualValue(items[idx], value)
    }

    func quickFixes(for item: MatchItem) -> [(title: String, value: String)] {
        SmartFiller.quickFixes(for: item, library: library)
    }

    func isEnumMismatch(_ item: MatchItem) -> Bool {
        SmartFiller.isEnumMismatch(item, dictionary: enumDictionary)
    }

    // MARK: 过滤

    var searchText: String = ""
    var confidenceFilter: ConfidenceFilter = .all
    var statusFilter: StatusFilter = .all
    var enumMismatchOnly: Bool = false

    enum ConfidenceFilter: String, CaseIterable {
        case all = "全部"
        case perfect = "100%匹配"
        case imperfect = "<100%匹配"
    }

    enum StatusFilter: String, CaseIterable {
        case all = "全部"
        case filled = "已填报"
        case empty = "未填报"
    }

    var filteredItems: [MatchItem] {
        var result = items

        let keywords = searchText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        if !keywords.isEmpty {
            result = result.filter { m in
                keywords.contains { kw in
                    m.requirementName.lowercased().contains(kw)
                        || m.matchedParam?.name.lowercased().contains(kw) ?? false
                        || m.matchedParam?.displayValue.lowercased().contains(kw) ?? false
                }
            }
        }

        switch confidenceFilter {
        case .all: break
        case .perfect:
            result = result.filter { Int(( $0.confidence * 100).rounded()) == 100 }
        case .imperfect:
            result = result.filter { Int(($0.confidence * 100).rounded()) < 100 }
        }

        switch statusFilter {
        case .all: break
        case .filled:
            result = result.filter { $0.isFilled }
        case .empty:
            result = result.filter { !$0.isFilled }
        }

        if enumMismatchOnly {
            result = result.filter { isEnumMismatch($0) }
        }
        return result
    }

    var enumMismatchItems: [MatchItem] {
        items.filter { isEnumMismatch($0) }
    }

    // MARK: 导出

    /// 置信度三色（旧版：>0.8 绿 / >0.5 橙 / 其余红）
    static func confidenceColor(_ confidence: Double) -> NSColor {
        confidence > 0.8 ? .systemGreen : (confidence > 0.5 ? .systemOrange : .systemRed)
    }

    func copyCSV() {
        let results = filteredItems
        guard !results.isEmpty else { return }
        var csv = "需求参数名,匹配库参数名,填报值,置信度,状态\n"
        for m in results {
            let fields = [
                m.requirementName,
                m.manualValue != nil ? "(手动输入)" : (m.matchedParam?.name ?? "(未匹配)"),
                m.effectiveValue,
                "\(Int((m.confidence * 100).rounded()))%",
                m.manualValue != nil ? "手动" : (m.matchedParam != nil ? "已匹配" : "未匹配"),
            ]
            csv += fields
                .map { $0.contains(",") || $0.contains("\"") ? "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" : $0 }
                .joined(separator: ",")
            csv += "\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
    }

    func copyEnumMismatches() {
        let mismatches = enumMismatchItems
        guard !mismatches.isEmpty else { return }
        var text = "参数名\t当前值\n"
        text += mismatches.map { "\($0.requirementName)\t\($0.effectiveValue)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportVehicleCloud() {
        let results = filteredItems
        guard !results.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")].compactMap { $0 }
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone.current
        let productName = selectedProduct ?? "未命名车型"
        panel.nameFieldStringValue = "车上云系统导入_\(productName)_\(formatter.string(from: date)).xlsx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try XlsxWriter.writeVehicleCloudTemplate(items: results, productName: productName, to: url, date: date)
            lastError = nil
        } catch {
            lastError = "导出失败：\(error.localizedDescription)"
        }
    }
}
