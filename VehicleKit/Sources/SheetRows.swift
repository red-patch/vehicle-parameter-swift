import CoreXLSX
import Foundation
import ZIPFoundation

// MARK: - 工作表行矩阵（与旧版 SheetJS sheet_to_json(header:1) 同构）
//
// 语义对齐要点（golden 契约的一部分）：
// - 行列越界按 undefined 处理（旧版 row[idx] 越界为 undefined，判空得 ''）
// - 每行长度截至该行最后一个非空单元格（SheetJS 尾部裁剪），中间空洞为 nil
// - 行列范围来自 sheet dimension；列跨度 > 512 时按真实单元格边界收敛
//   （对应旧版 getEffectiveSheetRange，防 !ref 膨胀到 XFD 的无效遍历）

/// 单元格原始值（JS 可见性三态：string | number | boolean）
public enum CellValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case bool(Bool)
    /// 内部中间态：t="s" 的共享字符串索引，buildGrid 阶段解析为 text
    case sharedIndex(Int)

    /// JS String(cell) 形态。
    /// number 用最短往返表示；整数不带小数点（与 JS 一致）。
    /// 已知偏差：|值| ≥ 1e21 或 < 1e-6 的非整数值，Swift 与 JS 的科学计数法
    /// 阈值不同——车辆参数域不会出现，golden 出现时再补格式化。
    public var jsString: String {
        switch self {
        case .text(let s): s
        case .bool(let b): b ? "true" : "false"
        case .number(let d): jsNumberString(d)
        case .sharedIndex: ""  // 中间态不直接参与文本化
        }
    }
}

@inline(__always)
func jsNumberString(_ d: Double) -> String {
    // JS Number 是 SAFE_INTEGER 域内的整数时输出整数形态
    if d.isFinite, d == d.rounded(), abs(d) <= 9_007_199_254_740_992 {
        return String(Int64(d))
    }
    return String(d)
}

/// 一个 sheet 的行矩阵（0 基；行数由 dimension 决定，含全空行）
public struct WorksheetGrid: Sendable {
    public let rows: [[CellValue?]]

    /// 越界安全取值：行列越界返回 nil（对应 JS undefined）
    public func cell(_ row: Int, _ col: Int) -> CellValue? {
        guard row >= 0, row < rows.count else { return nil }
        let r = rows[row]
        guard col >= 0, col < r.count else { return nil }
        return r[col]
    }

    /// 行的"JS 长度"（尾部裁剪后的长度）
    public func rowLength(_ row: Int) -> Int {
        row >= 0 && row < rows.count ? rows[row].count : 0
    }

    public var count: Int { rows.count }

    public var isEmpty: Bool { rows.allSatisfy { $0.isEmpty } }

    /// 行内是否有任何非空单元格（isFilled 语义：值存在且 trim 后非空）
    public func rowHasContent(_ row: Int) -> Bool {
        guard row >= 0, row < rows.count else { return false }
        return rows[row].contains { c in
            guard let c else { return false }
            return !c.jsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public struct NamedSheetGrid: Sendable {
    public let name: String
    public let grid: WorksheetGrid
}

public enum SheetGridError: Error, LocalizedError {
    case cannotOpen(String)
    case noWorkbook
    case relationshipUnresolved(sheet: String)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let path): "无法打开 xlsx 文件：\(path)"
        case .noWorkbook: "xlsx 文件缺少 workbook.xml"
        case .relationshipUnresolved(let sheet): "工作表 \(sheet) 的关系引用无法解析"
        }
    }
}

// MARK: - 加载

/// 原始关系条目（不限定 SchemaType，兼容 WPS/SheetJS 等写出的非标类型）
public struct RawRelationship: Sendable, Equatable {
    public let id: String
    public let type: String
    public let target: String
}

/// 用 XMLParser 读取 .rels（CoreXLSX 的 Relationships 解码对未知 Type 会抛错）
enum RelsParser {
    static func parse(_ data: Data) -> [RawRelationship] {
        final class Delegate: NSObject, XMLParserDelegate {
            var items: [RawRelationship] = []
            func parser(
                _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
            ) {
                guard elementName == "Relationship",
                      let id = attributeDict["Id"],
                      let type = attributeDict["Type"],
                      let target = attributeDict["Target"] else { return }
                items.append(RawRelationship(id: id, type: type, target: target))
            }
        }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }
}

public enum SheetGridLoader {
    /// 打开 xlsx 并按 workbook 声明序返回各 sheet 的行矩阵
    public static func load(url: URL) throws -> [NamedSheetGrid] {
        guard let file = XLSXFile(filepath: url.path) else {
            throw SheetGridError.cannotOpen(url.lastPathComponent)
        }
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw SheetGridError.cannotOpen(url.lastPathComponent)
        }
        return try load(file: file, archive: archive)
    }

    public static func load(data: Data) throws -> [NamedSheetGrid] {
        guard let file = try? XLSXFile(data: data) else {
            throw SheetGridError.cannotOpen("data")
        }
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw SheetGridError.cannotOpen("data")
        }
        return try load(file: file, archive: archive)
    }

    public static func load(file: XLSXFile, archive: Archive) throws -> [NamedSheetGrid] {
        guard let workbook = try file.parseWorkbooks().first else {
            throw SheetGridError.noWorkbook
        }
        // 原始提取：保留 CRLF（CoreXLSX 的 XMLDecoder 会按 XML 规范归一为 LF）
        let sharedStrings: [String]
        if let raw = try? readEntry(archive, "xl/sharedStrings.xml") {
            sharedStrings = RawSharedStrings.parse(raw)
        } else {
            sharedStrings = []
        }

        // 根 rels → officeDocument（workbook.xml）路径
        let rootRels = RelsParser.parse(try readEntry(archive, "_rels/.rels"))
        let docPaths = rootRels
            .filter { $0.type.hasSuffix("/officeDocument") }
            .map { resolvePath(target: $0.target, from: "") }
        guard !docPaths.isEmpty else { throw SheetGridError.noWorkbook }

        // workbook rels → worksheet 路径（相对 rels 所在目录解析）
        var idToPath: [String: String] = [:]
        for docPath in docPaths {
            let dir = (docPath as NSString).deletingLastPathComponent
            let base = (docPath as NSString).lastPathComponent
            let relsPath = dir.isEmpty ? "_rels/\(base).rels" : "\(dir)/_rels/\(base).rels"
            guard let relsData = try? readEntry(archive, relsPath) else { continue }
            for rel in RelsParser.parse(relsData) where rel.type.hasSuffix("/worksheet") {
                idToPath[rel.id] = resolvePath(target: rel.target, from: dir)
            }
        }

        var sheets: [NamedSheetGrid] = []
        for sheet in workbook.sheets.items {
            guard let path = idToPath[sheet.relationship] else {
                throw SheetGridError.relationshipUnresolved(sheet: sheet.name ?? "?")
            }
            let data = try readEntry(archive, path)
            let parser = RawWorksheetParser()
            let rawRows = parser.parse(data)
            let grid = buildGrid(
                dimensionRef: parser.dimensionRef,
                rawRows: rawRows,
                sharedStrings: sharedStrings
            )
            sheets.append(NamedSheetGrid(name: sheet.name ?? "", grid: grid))
        }
        return sheets
    }

    private static func readEntry(_ archive: Archive, _ path: String) throws -> Data {
        guard let entry = archive[path] else {
            throw SheetGridError.cannotOpen(path)
        }
        var data = Data()
        _ = try archive.extract(entry) { data += $0 }
        return data
    }

    /// rels target 相对路径解析（"worksheets/sheet1.xml" from "xl" → "xl/worksheets/sheet1.xml"）
    private static func resolvePath(target: String, from prefix: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        var parts = prefix.split(separator: "/").map(String.init)
        for seg in target.split(separator: "/") {
            switch seg {
            case "..": if !parts.isEmpty { parts.removeLast() }
            case ".": break
            default: parts.append(String(seg))
            }
        }
        return parts.joined(separator: "/")
    }
}

// MARK: - 原始共享字符串提取
//
// 不经过 XMLParser：规范 XML 解析器会把文本中的 \r\n 归一为 \n（XML 1.0 行尾规范化），
// 而 SheetJS（旧版）保留原始 CRLF。golden 契约要求保留原始字节。

enum RawSharedStrings {
    /// 解析 xl/sharedStrings.xml → 有序字符串数组（富文本 run 拼接）
    static func parse(_ data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var results: [String] = []
        var searchRange = xml.startIndex..<xml.endIndex
        while let siOpen = xml.range(of: "<si>", range: searchRange) {
            let blockStart = siOpen.upperBound
            guard let siClose = xml.range(of: "</si>", range: blockStart..<xml.endIndex) else { break }
            let block = xml[blockStart..<siClose.lowerBound]

            var text = ""
            var tSearch = block.startIndex..<block.endIndex
            while let tOpen = block.range(of: "<t", range: tSearch) {
                guard let tagEnd = block.range(of: ">", range: tOpen.upperBound..<block.endIndex) else { break }
                // 自闭合 <t/>：空文本
                if block[block.index(before: tagEnd.lowerBound)] == "/" {
                    tSearch = tagEnd.upperBound..<block.endIndex
                    continue
                }
                guard let tClose = block.range(of: "</t>", range: tagEnd.upperBound..<block.endIndex) else { break }
                text += unescapeXML(String(block[tagEnd.upperBound..<tClose.lowerBound]))
                tSearch = tClose.upperBound..<block.endIndex
            }
            results.append(text)
            searchRange = siClose.upperBound..<xml.endIndex
        }
        return results
    }

    /// 仅反转义 XML 实体（保留 \r\n 原样）
    static func unescapeXML(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = ""
        var iterator = s.unicodeScalars.makeIterator()
        var pending = ""
        func flushPending() { result += pending; pending = "" }
        while let scalar = iterator.next() {
            if scalar != "&" {
                pending.unicodeScalars.append(scalar)
                continue
            }
            flushPending()
            var entity = ""
            var matched = false
            while let next = iterator.next() {
                entity.unicodeScalars.append(next)
                if next == ";" { matched = true; break }
                if entity.unicodeScalars.count > 10 { break }  // 防御性上限
            }
            switch entity {
            case "lt;": result += "<"
            case "gt;": result += ">"
            case "amp;": result += "&"
            case "quot;": result += "\""
            case "apos;": result += "'"
            default:
                if matched, entity.hasPrefix("#") {
                    let digits = entity.dropFirst().dropLast()
                    let value: UInt32?
                    if digits.hasPrefix("x") || digits.hasPrefix("X") {
                        value = UInt32(digits.dropFirst(), radix: 16)
                    } else {
                        value = UInt32(digits)
                    }
                    if let value, let scalar = Unicode.Scalar(value) {
                        result.unicodeScalars.append(scalar)
                        continue
                    }
                }
                result += "&" + entity
            }
        }
        flushPending()
        return result
    }
}

// MARK: - 原始 worksheet 解析
//
// 用 XMLParser（libxml2 级速度）替代 CoreXLSX 的 XMLCoder 解码：
// 万格级横向 sheet（如 27 行 × 620 列的产品准入导出）在 XMLCoder 下需 2s+。
// 共享字符串经 RawSharedStrings 保留 CRLF；内联字符串经 XMLParser 会按 XML 规范
// 把 \r\n 归一为 \n（极少出现的已知偏差）。

struct RawRow {
    let index: Int  // 1 基行号
    var cells: [(col: Int, value: CellValue?)] = []  // col 0 基
}

final class RawWorksheetParser: NSObject, XMLParserDelegate {
    private(set) var dimensionRef: String?
    private(set) var rows: [RawRow] = []

    private var currentRow: RawRow?
    private var cellCol: Int?
    private var cellType: String?
    private var cellValueText: String?
    private var capturingText = false
    private var inlineRuns: String?
    private var inInlineString = false

    func parse(_ data: Data) -> [RawRow] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.parse()
        return rows
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "dimension":
            dimensionRef = attributeDict["ref"]
        case "row":
            currentRow = RawRow(index: attributeDict["r"].flatMap(Int.init) ?? (rows.count + 1))
        case "c":
            if let ref = attributeDict["r"] {
                let letters = ref.prefix { !$0.isNumber }
                cellCol = columnIndex(of: String(letters))
            }
            cellType = attributeDict["t"]
            cellValueText = nil
            inlineRuns = nil
        case "v":
            capturingText = true
            cellValueText = ""
        case "is":
            inInlineString = true
        case "t" where inInlineString:
            capturingText = true
            if cellValueText == nil { cellValueText = "" }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText { cellValueText? += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABuffer: Data) {
        if capturingText, let s = String(data: CDATABuffer, encoding: .utf8) {
            cellValueText? += s
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v", "t":
            capturingText = false
            if elementName == "t", inInlineString {
                inlineRuns = (inlineRuns ?? "") + (cellValueText ?? "")
                cellValueText = nil
            }
        case "is":
            inInlineString = false
        case "c":
            defer {
                cellCol = nil
                cellType = nil
                cellValueText = nil
                inlineRuns = nil
            }
            guard let col = cellCol else { return }
            let value = makeCellValue(type: cellType, raw: cellValueText, inline: inlineRuns)
            if currentRow != nil, value != nil || inlineRuns != nil {
                currentRow?.cells.append((col, value))
            }
        case "row":
            if let row = currentRow {
                rows.append(row)
                currentRow = nil
            }
        default:
            break
        }
    }

    private func makeCellValue(type: String?, raw: String?, inline: String?) -> CellValue? {
        if type == "inlineStr" {
            guard let inline, !inline.isEmpty else { return nil }
            return .text(inline)
        }
        guard let raw else { return nil }
        switch type {
        case "s":
            // 共享字符串索引在调用侧解析（需要 RawSharedStrings 数组）
            guard let index = Int(raw) else { return nil }
            return .sharedIndex(index)
        case "b":
            return .bool(raw == "1")
        case "e", "d", "str":
            return .text(raw)
        default:  // "n" 或缺省
            if let d = Double(raw) { return .number(d) }
            return .text(raw)
        }
    }
}

// MARK: - 网格构建

private func buildGrid(dimensionRef: String?, rawRows: [RawRow], sharedStrings: [String]) -> WorksheetGrid {
    // 计算有效范围（0 基）
    var startRow = 0
    var startCol = 0
    var endRow = -1
    var endCol = -1

    if let ref = dimensionRef, let range = parseSheetRange(ref) {
        startRow = range.startRow
        startCol = range.startCol
        endRow = range.endRow
        endCol = range.endCol
    }
    if endRow < startRow || endCol < startCol {
        // dimension 缺失：按真实单元格边界
        for row in rawRows {
            endRow = max(endRow, row.index - 1)
            for cell in row.cells {
                endCol = max(endCol, cell.col)
            }
        }
    } else if endCol - startCol + 1 > 512 {
        // 列跨度异常膨胀：按真实单元格边界收敛（getEffectiveSheetRange 语义）
        var minR = Int.max, maxR = -1, minC = Int.max, maxC = -1
        for row in rawRows {
            let r = row.index - 1
            for cell in row.cells {
                minR = min(minR, r); maxR = max(maxR, r)
                minC = min(minC, cell.col); maxC = max(maxC, cell.col)
            }
        }
        if maxR >= minR && maxC >= minC {
            startRow = minR; startCol = minC; endRow = maxR; endCol = maxC
        }
    }

    let rowCount = max(0, endRow - startRow + 1)
    guard rowCount > 0 else { return WorksheetGrid(rows: []) }

    var rows: [[CellValue?]] = Array(repeating: [], count: rowCount)
    for row in rawRows {
        let rIdx = row.index - 1 - startRow
        guard rIdx >= 0, rIdx < rowCount else { continue }
        var cells: [Int: CellValue] = [:]
        var lastCol = -1
        for cell in row.cells {
            let cIdx = cell.col - startCol
            guard cIdx >= 0, cIdx <= endCol - startCol else { continue }
            let value: CellValue?
            switch cell.value {
            case .sharedIndex(let index):
                value = (index >= 0 && index < sharedStrings.count) ? .text(sharedStrings[index]) : nil
            default:
                value = cell.value
            }
            if let value {
                cells[cIdx] = value
                lastCol = max(lastCol, cIdx)
            }
        }
        if lastCol < 0 {
            rows[rIdx] = []
        } else {
            var array = [CellValue?](repeating: nil, count: lastCol + 1)
            for (c, v) in cells { array[c] = v }
            rows[rIdx] = array
        }
    }
    return WorksheetGrid(rows: rows)
}

/// 列字母（"A"、"AB"）→ 0 基索引
func columnIndex(of letters: String) -> Int {
    var value = 0
    for scalar in letters.unicodeScalars {
        guard (65...90).contains(scalar.value) else { continue }
        value = value * 26 + Int(scalar.value - 64)  // 'A' = 65
    }
    return value - 1
}

/// "A1:F10" → 0 基行列范围
private func parseSheetRange(_ ref: String) -> (startRow: Int, startCol: Int, endRow: Int, endCol: Int)? {
    let parts = ref.split(separator: ":")
    func parseCell(_ s: Substring) -> (row: Int, col: Int)? {
        var letters = ""
        var digits = ""
        for ch in s {
            if ch.isNumber { digits += String(ch) } else { letters += String(ch) }
        }
        guard let row = Int(digits), row > 0, !letters.isEmpty else { return nil }
        return (row - 1, columnIndex(of: letters))
    }
    guard let start = parseCell(parts[0]) else { return nil }
    let endCell = parts.count > 1 ? (parseCell(parts[1]) ?? start) : start
    return (start.row, start.col, endCell.row, endCell.col)
}
