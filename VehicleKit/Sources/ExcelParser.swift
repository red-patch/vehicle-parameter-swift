import CoreXLSX
import Foundation

// MARK: - Excel 参数解析器（旧版 excelParser.ts + excelParserHorizontal.ts 直译）
//
// 支持三种布局的自动识别：纵向（参数名一列、产品多列）、键值对（两列）、
// 横向（参数为列、车型为行，如"产品准入导出"）。
// 表头关键词、跳过规则、跨行表头检测、百分比还原、跨 sheet 单产品合并等
// 语义均与旧版逐条对齐——它们共同决定 golden 四态计数。

// ===================== 常量 =====================

/// 表头行中用于识别"参数名"列的关键词
private let nameKeywords = ["参数项名称", "参数名", "Parameter Name", "功能项", "项目", "名称", "清单"]

/// 需要排除的 Sheet 名称关键词
private let excludedSheetKeywords = ["版本", "修改", "记录", "history", "revision", "log"]

/// 分组列关键词
private let groupKeywords = ["类别", "分组", "Group"]

/// 应被跳过的列头（完整匹配，小写）
private let skipHeaders: Set<String> = [
    "序号", "index", "no.", "类别", "分组", "group", "category",
    "说明", "description", "note", "备注", "comment",
    "填写说明", "单位", "unit", "属性",
    "参数值", "数值", "value",
]

/// 包含这些关键词的短列头应被跳过（参数名类）
private let nameLikeKeywords = [
    "参数名", "参数项名称", "name", "parameter", "项目", "功能项", "名称", "清单",
    "技术要求", "功能要求", "配置要求", "requirement", "req", "要求",
]

// 横向格式常量（excelParserHorizontal.ts）
private let horizontalMinCols = 10
private let headerCheckWindow = 20
private let identityHeaders: Set<String> = [
    "型号", "车型型号", "产品型号", "车辆型号", "整车公告号", "公告号", "公告型号", "准入编号", "VIN",
]
private let verticalKeywordBlockers = ["参数项名称", "参数名", "parameter name", "功能项", "清单", "类别", "分组"]
private let horizontalMetadataHeaders: Set<String> = [
    "项目代号", "产品等级标准", "需求描述", "车辆类型", "审批状态", "准入编号",
    "状态", "整车公告号", "公告号id", "品牌", "型号", "公告批次",
]
private let horizontalMetadataGroup = "准入信息"
private let horizontalDefaultGroup = "基础信息"
private let dedupeHeader = "准入编号"

private struct ProductNamePart {
    let exact: [String]
    let loose: String?
}

/// 车型命名模板：按顺序取列值、非空部分用空格拼接
private let horizontalProductNameParts: [ProductNamePart] = [
    .init(exact: ["型号"], loose: "^(车辆|车型|产品)型号$"),
    .init(exact: ["动力电池包厂商"], loose: "^动力电池.{0,6}厂商$"),
    .init(exact: ["动力电池包电量（kWh）", "动力电池包电量(kWh)", "动力电池包电量"], loose: "^动力电池.{0,6}电量"),
    .init(exact: ["整车公告号"], loose: "^整车?公告号$"),
    .init(exact: ["产品等级标准"], loose: "等级"),
]

// ===================== 诊断与错误 =====================

public struct SkippedSheet: Sendable, Equatable {
    public let name: String
    public let reason: String
}

public struct ParseDiagnostics: Sendable, Equatable {
    public var totalSheets = 0
    public var sheetsProcessed: [String] = []
    public var sheetsSkipped: [SkippedSheet] = []
    public var headerFound = false
    public var productColumnsFound = 0
    public var suggestion = ""
}

public struct ParseError: Error, LocalizedError {
    public let message: String
    public let diagnostics: ParseDiagnostics

    public var errorDescription: String? { message }
}

// ===================== 公共工具函数 =====================

/// 智能百分比转换：Excel 存储 25% 为 0.25，需还原为 "25%"
private func convertPercentValue(_ value: CellValue?, name: String) -> String {
    if case .number(let d) = value, !name.isEmpty {
        let isPctField = name.contains("%") || name.contains("坡度") || name.contains("率") || name.contains("效率")
        if isPctField, d <= 1, d >= -1, d != 0 {
            // JS: parseFloat((value * 100).toFixed(2)) + '%'
            let scaled = ((d * 100) * 100).rounded() / 100
            return jsNumberString(scaled) + "%"
        }
    }
    return value?.jsString ?? ""
}

/// 从文件名提取产品名（支持中文文件名）
func extractProductNameFromFileName(_ fileName: String) -> String {
    var baseName = replaceRegex(fileName, pattern: "\\.[^/.]+$", with: "")
    baseName = baseName.split(separator: "/").last.map(String.init) ?? baseName
    if baseName.isEmpty { baseName = fileName }

    let cleaned = replaceRegex(baseName, pattern: "[_\\-]?(整车|配置|清单|参数表|面类|V\\d+).*$", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.utf16.count > 2 { return String(cleaned.prefix(30)) }
    // 兜底：取开头的字母数字+中文（JS \w = [A-Za-z0-9_]；ICU \u 只支持四位形式）
    if let m = captureRegex(baseName, pattern: "^([A-Za-z0-9_\\u4e00-\\u9fa5]+)"), let first = m.first {
        return String(first.prefix(30))
    }
    return String(baseName.prefix(20))
}

/// 从数据中智能推断产品名（型号字段值 + 公告号 → 型号 → 文件名）
func inferProductNameFromData(
    _ grid: WorksheetGrid, nameColIndex: Int, productColIndex: Int, dataStartRow: Int, fileName: String
) -> String {
    func findValue(_ keywords: [String]) -> String {
        let upper = min(grid.count, dataStartRow + 50)
        guard dataStartRow < upper else { return "" }
        for i in dataStartRow..<upper {
            guard let nameCell = grid.cell(i, nameColIndex), nameCell.isTruthy else { continue }
            let name = nameCell.trimmedString
            guard keywords.contains(name) else { continue }
            if let val = grid.cell(i, productColIndex), !val.trimmedString.isEmpty {
                return val.trimmedString
            }
        }
        return ""
    }

    let model = findValue(["型号", "车型型号"])
    let bulletin = findValue(["整车公告号", "公告号", "公告型号"])
    if !model.isEmpty, !bulletin.isEmpty { return "\(model) \(bulletin)" }
    if !model.isEmpty { return model }
    if !bulletin.isEmpty { return bulletin }
    return extractProductNameFromFileName(fileName)
}

/// 判断列头是否是占位符（如单独的"参数值"），需要下一行补充产品名
func isPlaceholderHeader(_ header: String) -> Bool {
    guard !header.isEmpty else { return false }
    let lower = header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["参数值", "数值", "value"].contains(lower)
}

/// 判断列头是否应被跳过（非产品列）
func shouldSkipColumn(_ header: String) -> Bool {
    if header.isEmpty { return true }
    let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    if skipHeaders.contains(lower) { return true }
    if trimmed.utf16.count < 20 {
        for kw in nameLikeKeywords where lower.contains(kw.lowercased()) {
            return true
        }
    }
    return false
}

/// 从列头提取产品名称
/// "参数值（栏板）（金旅ET850）" → "金旅ET850 栏板"；"参数值（产品名）" → "产品名"
func extractProductName(_ header: String) -> String? {
    let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let m = captureRegex(trimmed, pattern: "^(?:参数值|数值)[（(]([^）)]+)[）)][（(]([^）)]+)[）)]$") {
        return "\(m[1]) \(m[0])"
    }
    if let m = captureRegex(trimmed, pattern: "^(?:参数值|数值)[（(]([^）)]+)[）)]$") {
        return m.first ?? nil
    }
    if shouldSkipColumn(trimmed) { return nil }
    return trimmed
}

/// 严格检测是否为跨行表头。核心规则：单个"参数值"列 + 下一行有值 ≠ 跨行表头
func detectMultiRowHeader(
    _ headers: [CellValue?], _ nextRow: [CellValue?], nameIdx: Int, groupIdx: Int
) -> Bool {
    if nextRow.isEmpty { return false }

    let placeholderIndices = headers.indices.filter { idx in
        idx > nameIdx && idx != groupIdx && headers[idx].isTruthy
            && isPlaceholderHeader(headers[idx]!.trimmedString)
    }

    if placeholderIndices.count > 1 {
        let nextValues = placeholderIndices.map { idx -> String in
            guard let cell = at(nextRow, idx), cell.isTruthy else { return "" }
            return cell.trimmedString
        }.filter { !$0.isEmpty }
        return Set(nextValues).count > 1
    }

    if placeholderIndices.count == 1 {
        for idx in placeholderIndices {
            guard let nextCell = at(nextRow, idx), nextCell.isTruthy else { continue }
            let text = nextCell.trimmedString
            // 下一行内容较长且不是纯数值 → 是产品名
            if text.utf16.count > 2, !isPureNumeric(text) {
                return true
            }
        }
    }

    if placeholderIndices.count == 0 {
        for idx in (nameIdx + 1)..<headers.count where idx != groupIdx {
            let headerEmpty = at(headers, idx).map { $0.trimmedString.isEmpty } ?? true
            if headerEmpty, let next = at(nextRow, idx), next.isTruthy, !next.trimmedString.isEmpty {
                return true
            }
        }
    }

    return false
}

/// 判断 Sheet 名称是否属于应排除的辅助页（版本记录等）
func isExcludedSheet(_ sheetName: String) -> Bool {
    let lower = sheetName.lowercased()
    return excludedSheetKeywords.contains { lower.contains($0) }
}

/// 判断行是否为参数表表头（通过表头关键词，仅接受字符串单元格）
func isParameterSheet(_ headers: [CellValue?], sheetName: String) -> Bool {
    if isExcludedSheet(sheetName) { return false }
    return headers.contains { h in
        guard let h, case .text(let s) = h, !s.isEmpty else { return false }
        if s.utf16.count > 50 || s.contains("附件") || s.contains("Sheet") || s.contains("Table") {
            return false
        }
        return nameKeywords.contains { s.contains($0) }
    }
}

/// 检测键值对格式（两列：参数名 + 值）
func isKeyValueFormat(_ grid: WorksheetGrid) -> Bool {
    if grid.count < 5 { return false }
    let checkRows = min(20, grid.count)
    var validRows = 0
    for i in 0..<checkRows {
        guard !grid.rows[i].isEmpty else { continue }
        let nonEmpty = grid.rows[i].filter { c in
            guard let c else { return false }
            return !c.trimmedString.isEmpty
        }.count
        if (1...4).contains(nonEmpty) {
            if let first = grid.cell(i, 0), first.isTruthy, case .text(let s) = first {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.unicodeScalars.contains(where: { scalar in
                    (0x4E00...0x9FA5).contains(scalar.value) || scalar == "(" || scalar == "（"
                }) {
                    validRows += 1
                }
            }
        }
    }
    return Double(validRows) >= Double(checkRows) * 0.6
}

// MARK: 小工具

extension CellValue {
    /// JS truthiness
    var isTruthy: Bool {
        switch self {
        case .text(let s): !s.isEmpty
        case .number(let d): d != 0 && !d.isNaN
        case .bool(let b): b
        case .sharedIndex: false  // 中间态，网格构建后不存在
        }
    }

    var trimmedString: String {
        jsString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Optional where Wrapped == CellValue {
    var isTruthy: Bool { self?.isTruthy ?? false }
    var trimmedString: String { self?.trimmedString ?? "" }
}

@inline(__always)
private func at(_ array: [CellValue?], _ idx: Int) -> CellValue? {
    idx >= 0 && idx < array.count ? array[idx] : nil
}

private func isPureNumeric(_ s: String) -> Bool {
    captureRegex(s, pattern: "^(\\d+(\\.\\d+)?)$") != nil
}

func replaceRegex(_ input: String, pattern: String, with replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    return regex.stringByReplacingMatches(in: input, range: range, withTemplate: replacement)
}

/// 返回捕获组数组（index 0 = 组 1）
func captureRegex(_ input: String, pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    guard let m = regex.firstMatch(in: input, range: range) else { return nil }
    var groups: [String] = []
    for i in 1..<m.numberOfRanges {
        if let r = Range(m.range(at: i), in: input) {
            groups.append(String(input[r]))
        }
    }
    return groups
}

// ===================== 解析键值对格式 =====================

private func parseKeyValueSheet(_ grid: WorksheetGrid, sheetName: String, fileName: String) -> [VehicleParameter] {
    var parameters: [VehicleParameter] = []
    let productName = extractProductNameFromFileName(fileName)
    var currentGroup = "基础信息"

    for i in 0..<grid.count {
        guard let nameCell = grid.cell(i, 0) else { continue }
        let name = nameCell.trimmedString
        if name.isEmpty { continue }

        let valueCell = grid.cell(i, 1)
        // 分组标题检测：值缺省或与名称相同 + 短中文名 + 含组关键词
        let valueFalsy: Bool
        switch valueCell {
        case nil: valueFalsy = true
        case .text(let s): valueFalsy = s.isEmpty
        case .number(let d): valueFalsy = d == 0
        case .bool(let b): valueFalsy = !b
        case .sharedIndex: valueFalsy = true
        }
        let sameAsName = nameCell == valueCell
        let hasCJK = name.unicodeScalars.contains { (0x4E00...0x9FA5).contains($0.value) }
        if (valueFalsy || sameAsName), name.utf16.count < 15, hasCJK {
            if name.contains("信息") || name.contains("系统") || name.contains("配置") || name.contains("参数") {
                currentGroup = name
                continue
            }
        }

        parameters.append(VehicleParameter(
            id: "\(sheetName)::\(productName)::\(currentGroup)::\(name)",
            group: currentGroup,
            name: name,
            value: .string(valueCell?.trimmedString ?? ""),
            originSheet: sheetName,
            productName: productName
        ))
    }
    return parameters
}

// ===================== 横向格式（excelParserHorizontal.ts） =====================

public struct HorizontalSheetInfo: Sendable, Equatable {
    public let headerRowIndex: Int
    public let totalCols: Int
}

/// 检测 sheet 是否为横向格式（参数为列、车型为行）
func detectHorizontalSheet(_ grid: WorksheetGrid) -> HorizontalSheetInfo? {
    // 找表头候选行：第一个宽度达标的非空行
    var candidateIdx = -1
    var totalCols = 0
    for i in 0..<min(grid.count, 10) {
        guard grid.rowHasContent(i) else { continue }
        let len = grid.rowLength(i)
        if len >= horizontalMinCols {
            candidateIdx = i
            totalCols = len
            break
        }
    }
    guard candidateIdx >= 0 else { return nil }

    let headerRow = trimmedRowStrings(grid, candidateIdx)
    let checkWidth = min(headerRow.count, headerCheckWindow)
    if checkWidth < horizontalMinCols { return nil }

    // 表头填充率（前 20 列 ≥ 80%）
    let filled = headerRow.prefix(checkWidth).filter { !$0.isEmpty }.count
    if Double(filled) / Double(checkWidth) < 0.8 { return nil }

    // 纵向强关键词列 → 交给纵向解析
    let blocked = headerRow.prefix(checkWidth).contains { h in
        !h.isEmpty && verticalKeywordBlockers.contains { h.lowercased().contains($0) }
    }
    if blocked { return nil }

    // 车型标识表头（精确匹配）
    guard let identityIdx = headerRow.prefix(checkWidth).firstIndex(where: { identityHeaders.contains($0) })
    else { return nil }

    // 标识列下方必须有数据（排除恰好很宽的普通文本行）
    var hasData = false
    for r in (candidateIdx + 1)..<min(candidateIdx + 11, grid.count) {
        if grid.cell(r, identityIdx).isTruthy {
            hasData = true
            break
        }
    }
    guard hasData else { return nil }

    return HorizontalSheetInfo(headerRowIndex: candidateIdx, totalCols: totalCols)
}

private func trimmedRowStrings(_ grid: WorksheetGrid, _ row: Int) -> [String] {
    (0..<grid.rowLength(row)).map { c in grid.cell(row, c)?.trimmedString ?? "" }
}

private func findPartColumn(_ headers: [String], _ part: ProductNamePart, _ used: Set<Int>) -> Int {
    for exact in part.exact {
        if let idx = headers.firstIndex(of: exact), !used.contains(idx) {
            return idx
        }
    }
    if let loose = part.loose {
        if let idx = headers.indices.first(where: { i in
            !used.contains(i) && !headers[i].isEmpty
                && captureRegex(headers[i], pattern: loose) != nil
        }) {
            return idx
        }
    }
    return -1
}

/// 解析横向 sheet：每个数据行 → 一个车型，每个非空表头列 → 一条参数
func parseHorizontalSheet(_ grid: WorksheetGrid, info: HorizontalSheetInfo, sheetName: String) -> [VehicleParameter] {
    let headers = trimmedRowStrings(grid, info.headerRowIndex)

    var usedCols = Set<Int>()
    let partCols = horizontalProductNameParts.map { part -> Int in
        let idx = findPartColumn(headers, part, usedCols)
        if idx >= 0 { usedCols.insert(idx) }
        return idx
    }
    let dedupeCol = headers.firstIndex(of: dedupeHeader) ?? -1

    // 逐行生成车型名（重名时用准入编号去重，仍重名追加序号）
    var usedNames = Set<String>()
    var dataRows: [(rowIndex: Int, productName: String)] = []
    for i in (info.headerRowIndex + 1)..<grid.count {
        guard grid.rowHasContent(i) else { continue }

        let parts = partCols.map { col -> String in
            guard col >= 0 else { return "" }
            return grid.cell(i, col)?.trimmedString ?? ""
        }.filter { !$0.isEmpty }
        var base = parts.joined(separator: " ")
        if base.isEmpty { base = "第\(i + 1)行" }

        var name = base
        if usedNames.contains(name) {
            let admission = dedupeCol >= 0 ? (grid.cell(i, dedupeCol)?.trimmedString ?? "") : ""
            let withAdmission = admission.isEmpty ? "" : "\(base) (\(admission))"
            if !withAdmission.isEmpty, !usedNames.contains(withAdmission) {
                name = withAdmission
            } else {
                let stem = withAdmission.isEmpty ? base : withAdmission
                var seq = 2
                while usedNames.contains("\(stem)-\(seq)") { seq += 1 }
                name = "\(stem)-\(seq)"
            }
        }
        usedNames.insert(name)
        dataRows.append((i, name))
    }

    var parameters: [VehicleParameter] = []
    for entry in dataRows {
        for c in 0..<headers.count {
            let name = headers[c]
            if name.isEmpty { continue }
            let group = horizontalMetadataHeaders.contains(name)
                ? horizontalMetadataGroup
                : horizontalDefaultGroup
            let value = convertPercentValue(grid.cell(entry.rowIndex, c), name: name)
            parameters.append(VehicleParameter(
                id: "\(sheetName)::\(entry.productName)::\(group)::\(name)",
                group: group,
                name: name,
                value: .string(value),
                originSheet: sheetName,
                productName: entry.productName
            ))
        }
    }
    return parameters
}

// ===================== 核心自动解析 =====================

public enum ExcelParser {
    /// 解析 xlsx 文件（对应旧版 parseExcel）
    public static func parse(url: URL) throws -> SheetData {
        let sheets = try SheetGridLoader.load(url: url)
        return try parseWorkbook(sheets, fileName: url.lastPathComponent)
    }

    public static func parse(data: Data, fileName: String) throws -> SheetData {
        let sheets = try SheetGridLoader.load(data: data)
        return try parseWorkbook(sheets, fileName: fileName)
    }

    /// 核心自动解析（对应旧版 parseWorkbook(workbook, fileName)）
    public static func parseWorkbook(_ sheets: [NamedSheetGrid], fileName: String) throws -> SheetData {
        var allParameters: [VehicleParameter] = []
        var rawHeaders: [String] = []
        var horizontalSheetNames = Set<String>()

        var diagnostics = ParseDiagnostics()
        diagnostics.totalSheets = sheets.count

        for sheet in sheets {
            let sheetName = sheet.name
            let grid = sheet.grid

            if grid.rows.isEmpty {
                diagnostics.sheetsSkipped.append(SkippedSheet(name: sheetName, reason: "Sheet为空"))
                continue
            }

            // 优先检测横向格式（参数为列、车型为行，如"产品准入导出"）
            if !isExcludedSheet(sheetName), let horizontalInfo = detectHorizontalSheet(grid) {
                let params = parseHorizontalSheet(grid, info: horizontalInfo, sheetName: sheetName)
                if !params.isEmpty {
                    allParameters.append(contentsOf: params)
                    horizontalSheetNames.insert(sheetName)
                    diagnostics.headerFound = true
                    diagnostics.productColumnsFound += Set(params.map(\.productName)).count
                    diagnostics.sheetsProcessed.append(sheetName)
                    continue
                }
            }

            // 检测键值对格式
            if isKeyValueFormat(grid) {
                allParameters.append(contentsOf: parseKeyValueSheet(grid, sheetName: sheetName, fileName: fileName))
                diagnostics.sheetsProcessed.append(sheetName)
                continue
            }

            // 1. 查找表头行
            var headerRowIndex = -1
            var currentHeaders: [CellValue?] = []
            for i in 0..<min(grid.count, 20) {
                if isParameterSheet(grid.rows[i], sheetName: sheetName) {
                    headerRowIndex = i
                    currentHeaders = grid.rows[i]
                    break
                }
            }

            if headerRowIndex == -1 {
                diagnostics.sheetsSkipped.append(
                    SkippedSheet(name: sheetName, reason: "未找到包含\"参数项名称\"或\"名称\"的表头行"))
                continue
            }
            diagnostics.headerFound = true
            if rawHeaders.isEmpty {
                rawHeaders = currentHeaders.map { $0?.jsString ?? "" }
            }

            // 2. 识别参数名列和分组列（仅接受字符串单元格）
            let nameIdx = currentHeaders.firstIndex { h in
                guard let h, case .text(let s) = h else { return false }
                return !s.contains("附件") && nameKeywords.contains { s.contains($0) }
            } ?? -1
            let groupIdx = currentHeaders.firstIndex { h in
                guard let h, case .text(let s) = h else { return false }
                return groupKeywords.contains { s.contains($0) }
            } ?? -1
            if nameIdx == -1 { continue }

            // 3. 跨行表头检测
            let nextRow: [CellValue?] = headerRowIndex + 1 < grid.count ? grid.rows[headerRowIndex + 1] : []
            let isMultiRow = detectMultiRowHeader(currentHeaders, nextRow, nameIdx: nameIdx, groupIdx: groupIdx)
            let dataStartRow = isMultiRow ? headerRowIndex + 2 : headerRowIndex + 1

            let placeholderCount = currentHeaders.indices.filter { idx in
                idx > nameIdx && idx != groupIdx && currentHeaders[idx].isTruthy
                    && isPlaceholderHeader(currentHeaders[idx]!.trimmedString)
            }.count

            // 4. 识别产品列
            var productIndices: [Int] = []
            var productNames: [Int: String] = [:]
            let maxCol = isMultiRow ? max(currentHeaders.count, nextRow.count) : currentHeaders.count

            for idx in 0..<maxCol {
                if idx == groupIdx || idx == nameIdx || idx < nameIdx { continue }

                let headerCell = at(currentHeaders, idx)
                let headerStr = headerCell.isTruthy ? headerCell.trimmedString : ""
                var productName: String? = nil

                // 尝试从当前行提取
                if headerCell.isTruthy {
                    productName = extractProductName(headerCell!.jsString)
                }

                // 跨行表头：尝试从下一行提取
                if (productName == nil || productName!.isEmpty || isPlaceholderHeader(headerStr)) && isMultiRow {
                    let nextCell = at(nextRow, idx)
                    if nextCell.isTruthy {
                        if let extracted = extractProductName(nextCell!.jsString) {
                            productName = extracted
                        }
                    }
                }

                // 单占位符列：从数据中智能推断产品名
                if (productName == nil || productName!.isEmpty),
                   isPlaceholderHeader(headerStr), placeholderCount == 1 {
                    let inferred = inferProductNameFromData(
                        grid, nameColIndex: nameIdx, productColIndex: idx,
                        dataStartRow: dataStartRow, fileName: fileName)
                    if !inferred.isEmpty { productName = inferred }
                }

                guard let productName, !productName.isEmpty else { continue }
                productIndices.append(idx)
                productNames[idx] = productName
            }

            diagnostics.productColumnsFound += productIndices.count
            if !productIndices.isEmpty {
                diagnostics.sheetsProcessed.append(sheetName)
            } else {
                diagnostics.sheetsSkipped.append(
                    SkippedSheet(name: sheetName, reason: "未找到产品列（表头右侧应有产品名称列）"))
            }

            // 5. 提取数据（Fill-Down 分组）
            var lastGroup = "基础信息"
            guard dataStartRow < grid.count else { continue }
            for i in dataStartRow..<grid.count {
                var group = lastGroup
                if groupIdx != -1 {
                    if let cell = grid.cell(i, groupIdx), cell.isTruthy {
                        group = cell.trimmedString
                        lastGroup = group
                    }
                } else {
                    group = "Default"
                }

                let name = grid.cell(i, nameIdx)?.trimmedString ?? ""
                if name.isEmpty { continue }

                for pIdx in productIndices {
                    let pName = productNames[pIdx] ?? at(currentHeaders, pIdx).trimmedString
                    let value = convertPercentValue(grid.cell(i, pIdx), name: name)
                    allParameters.append(VehicleParameter(
                        id: "\(sheetName)::\(pName)::\(group)::\(name)",
                        group: group,
                        name: name,
                        value: .string(value),
                        originSheet: sheetName,
                        productName: pName
                    ))
                }
            }
        }

        if allParameters.isEmpty {
            if !diagnostics.headerFound {
                diagnostics.suggestion =
                    "请确保文件中包含\"参数项名称\"或\"名称\"列作为表头，或表头为\"参数作列、车型作行\"的横向格式（如产品准入导出）"
            } else if diagnostics.productColumnsFound == 0 {
                diagnostics.suggestion = "请确保表头行右侧有产品名称列，或在下一行填写产品名称"
            } else {
                diagnostics.suggestion = "请检查文件格式是否符合车辆参数表格式"
            }
            throw ParseError(message: "无法解析文件，未找到有效的参数数据", diagnostics: diagnostics)
        }

        // 跨 sheet 合并：同一文件多个 sheet 各产出单产品时，统一产品名。
        // 横向 sheet（_part0/_part1 分片）每行即一个车型，不参与此合并。
        var sheetOrder: [String] = []
        var productsBySheet: [String: [String]] = [:]
        for p in allParameters {
            let sheet = p.originSheet ?? ""
            if horizontalSheetNames.contains(sheet) { continue }
            if productsBySheet[sheet] == nil {
                productsBySheet[sheet] = []
                sheetOrder.append(sheet)
            }
            let name = p.productName ?? ""
            if !(productsBySheet[sheet]?.contains(name) ?? true) {
                productsBySheet[sheet]?.append(name)
            }
        }
        let allSingleProduct = sheetOrder.allSatisfy { (productsBySheet[$0]?.count ?? 0) == 1 }
        if allSingleProduct, sheetOrder.count > 1 {
            let allNames = sheetOrder.compactMap { productsBySheet[$0]?.first }
            let uniqueNames = Set(allNames)
            // 最长名（同长取先出现者，对应旧版 reduce 语义）
            if uniqueNames.count > 1, var bestName = allNames.first {
                for n in allNames.dropFirst() where n.utf16.count > bestName.utf16.count {
                    bestName = n
                }
                for i in allParameters.indices {
                    allParameters[i].productName = bestName
                }
            }
        }

        return SheetData(fileName: fileName, data: allParameters, rawHeaders: rawHeaders)
    }
}
