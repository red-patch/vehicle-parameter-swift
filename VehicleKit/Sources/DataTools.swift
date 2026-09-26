import Foundation

// MARK: - 属性池去重（旧版 AttributeDedup.tsx 域侧语义直译）
//
// 输入：属性池 Excel（表头含「属性名称」「是否必填」，sheet_to_json 对象模式）。
// 规则：按「属性名称」去重，保留首次出现的「是否必填」值。

public struct AttributeRow: Identifiable, Hashable, Sendable {
    public var id: Int  // 序号（0 基）
    public var name: String
    public var required: String

    public init(id: Int, name: String, required: String) {
        self.id = id
        self.name = name
        self.required = required
    }
}

public enum AttributeDedup {
    public enum DedupError: Error, LocalizedError {
        case emptyFile
        case missingNameColumn

        public var errorDescription: String? {
            switch self {
            case .emptyFile: "文件内容为空"
            case .missingNameColumn: "文件缺少「属性名称」列"
            }
        }
    }

    /// 解析属性池行矩阵（首个 sheet）并去重。
    /// 旧版 sheet_to_json 以表头为键取「属性名称」/「是否必填」列；
    /// 这里按表头行定位两列的列索引，语义等价（同名表头取首个）。
    public static func dedupe(grid: WorksheetGrid) throws -> [AttributeRow] {
        // 定位表头行与前几列内的表头键
        guard let header = grid.rows.first(where: { row in
            row.contains { $0?.jsString.trimmingCharacters(in: .whitespaces) == "属性名称" }
        }) else {
            throw DedupError.missingNameColumn
        }
        let nameCol = header.firstIndex {
            $0?.jsString.trimmingCharacters(in: .whitespaces) == "属性名称"
        } ?? -1
        let requiredCol = header.firstIndex {
            $0?.jsString.trimmingCharacters(in: .whitespaces) == "是否必填"
        } ?? -1
        let headerRow = grid.rows.firstIndex {
            $0.contains { $0?.jsString.trimmingCharacters(in: .whitespaces) == "属性名称" }
        } ?? 0

        // 首见保留（Map.has 检查），required 取首行值（缺失记 ""）
        var uniqueMap: [String: String] = [:]
        var order: [String] = []
        for i in (headerRow + 1)..<grid.count {
            let name = grid.cell(i, nameCol)?.jsString.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty else { continue }
            guard uniqueMap[name] == nil else { continue }
            let required = requiredCol >= 0
                ? (grid.cell(i, requiredCol)?.jsString.trimmingCharacters(in: .whitespaces) ?? "")
                : ""
            uniqueMap[name] = required
            order.append(name)
        }
        return order.enumerated().map { index, name in
            AttributeRow(id: index, name: name, required: uniqueMap[name] ?? "")
        }
    }

    /// 从文件解析并去重（取第一个 sheet）
    public static func dedupe(url: URL) throws -> [AttributeRow] {
        let sheets = try SheetGridLoader.load(url: url)
        guard let first = sheets.first, !first.grid.rows.isEmpty else {
            throw DedupError.emptyFile
        }
        return try dedupe(grid: first.grid)
    }

    /// 导出 CSV（与旧版 handleExport 一致：引号包裹 + 双引号转义）
    public static func csvContent(_ rows: [AttributeRow]) -> String {
        let quote = { (s: String) in "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        let lines = ["属性名称,是否必填"]
            + rows.map { "\(quote($0.name)),\(quote($0.required))" }
        return lines.joined(separator: "\n")
    }

    /// 导出文件名（与旧版一致：原名替换扩展为 _去重.csv）
    public static func outputFileName(for input: String) -> String {
        let stripped = input.replacingOccurrences(
            of: "\\.(xlsx|xls)$", with: "", options: [.regularExpression, .caseInsensitive])
        return "\(stripped)_去重.csv"
    }
}

// MARK: - 公告查询（旧版 AnnouncementQuery.tsx 域侧语义直译）

public enum AnnouncementQuery {
    public static let miitQueryURL =
        "https://service.miit-eidc.org.cn/miitxxgk/gonggao/xxgk/index"

    /// 构建查询 URL（公告号 percent-encode）
    public static func queryURL(for announcementNo: String) -> URL? {
        var components = URLComponents(string: miitQueryURL)
        components?.queryItems = [
            URLQueryItem(name: "querylb", value: "cp"),
            URLQueryItem(name: "querydata", value: announcementNo),
        ]
        return components?.url
    }

    /// 书签脚本（与旧版 BOOKMARKLET_CODE 一致，供展示与复制）
    public static let bookmarkletCode =
        "javascript:(function(){try{const table=document.querySelector('table.query_result_table');if(!table){alert('未找到参数表，请确保在参数详情页使用此书签。');return;}const results=[];const rows=Array.from(table.querySelectorAll('tr'));rows.forEach(row=>{const cells=Array.from(row.querySelectorAll('td'));if(cells.length>=4){const k1=cells[0].innerText.trim();const v1=cells[1].innerText.trim();const k2=cells[2].innerText.trim();const v2=cells[3].innerText.trim();if(k1)results.push({name:k1,value:v1,group:'工信部数据'});if(k2)results.push({name:k2,value:v2,group:'工信部数据'});}else if(cells.length>=2){const k=cells[0].innerText.trim();const v=cells[1].innerText.trim();if(k)results.push({name:k,value:v,group:'工信部数据'});}});const data={source:'miit-helper',parameters:results};const json=JSON.stringify(data);navigator.clipboard.writeText(json).then(()=>{alert('已成功复制 '+results.length+' 条参数到剪贴板！\\n请返回车辆参数工具粘贴导入。');}).catch(err=>{const i=document.createElement('textarea');i.value=json;document.body.appendChild(i);i.select();document.execCommand('copy');document.body.removeChild(i);alert('已成功复制 '+results.length+' 条参数到剪贴板！');});}catch(e){alert('发生错误: '+e.message);}})();"

    /// 书签导入 JSON 结构
    private struct BookmarkPayload: Decodable {
        let source: String
        let parameters: [BookmarkParam]
    }

    private struct BookmarkParam: Decodable {
        let name: String
        let value: String?
        let group: String?
    }

    public enum ImportError: Error, LocalizedError {
        case badFormat
        case badJSON

        public var errorDescription: String? {
            switch self {
            case .badFormat: "数据格式不正确，请确保复制的是书签脚本生成的数据"
            case .badJSON: "解析JSON失败，请检查粘贴内容"
            }
        }
    }

    /// 解析书签粘贴导入（含「其它」字段拆分，与旧版逐条一致）
    public static func parseImport(
        _ jsonText: String, announcementNo: String = ""
    ) throws -> SheetData {
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BookmarkPayload.self, from: data) else {
            throw ImportError.badJSON
        }
        guard payload.source == "miit-helper" else {
            throw ImportError.badFormat
        }

        var parsed: [VehicleParameter] = []
        let fallbackName = announcementNo.trimmingCharacters(in: .whitespaces).isEmpty
            ? "工信部数据导入" : announcementNo.trimmingCharacters(in: .whitespaces)

        for (index, p) in payload.parameters.enumerated() {
            let group = p.group ?? "基础信息"
            let value = p.value ?? ""

            if p.name == "其它", !value.isEmpty {
                // 保留原始字段
                parsed.append(VehicleParameter(
                    id: "miit-\(index)-origin", group: group, name: p.name,
                    value: .string(value), originSheet: "工信部官网"))

                // 拆分子字段：优先分号；无效时按点号分隔（排除数字中间的小数点）
                var parts = value.components(separatedBy: CharacterSet(charactersIn: ";；"))
                if parts.count <= 1, value.contains(".") {
                    parts = splitDotted(value)
                }
                for (subIndex, part) in parts.enumerated() {
                    let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    // captureRegex 跳过未参与的捕获组，故按返回组数显式分支：
                    // "1.key:value" → [seq, key, value]；"key:value" → [key, value]
                    if let m = captureRegex(trimmed, pattern: "^(?:(\\d+)\\.)?([^:：]+)[:：](.+)$") {
                        let (key, val): (String, String)
                        switch m.count {
                        case 3: (key, val) = (m[1], m[2])
                        case 2: (key, val) = (m[0], m[1])
                        default: continue
                        }
                        parsed.append(VehicleParameter(
                            id: "miit-\(index)-sub-\(subIndex)",
                            group: "其它-详细参数",
                            name: key.trimmingCharacters(in: .whitespaces),
                            value: .string(val.trimmingCharacters(in: .whitespaces)),
                            originSheet: "工信部官网"))
                    } else if let m = captureRegex(trimmed, pattern: "^(?:(\\d+)\\.)?(.+)$") {
                        // 纯文本 "1.text" → [seq, text]；"text" → [text]
                        let suffix: String
                        let text: String
                        switch m.count {
                        case 2: (suffix, text) = (m[0], m[1])
                        case 1: (suffix, text) = ("\(subIndex + 1)", m[0])
                        default: continue
                        }
                        parsed.append(VehicleParameter(
                            id: "miit-\(index)-sub-\(subIndex)",
                            group: "其它-详细参数",
                            name: "其它-\(suffix)",
                            value: .string(text.trimmingCharacters(in: .whitespaces)),
                            originSheet: "工信部官网"))
                    }
                }
            } else {
                parsed.append(VehicleParameter(
                    id: "miit-\(index)", group: group, name: p.name,
                    value: .string(value), originSheet: "工信部官网"))
            }
        }

        return SheetData(fileName: fallbackName, data: parsed, rawHeaders: ["参数名", "值"])
    }

    /// JS value.split(/\.(?!\d)/)：点号后不跟数字才切分
    static func splitDotted(_ value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        let scalars = Array(value)
        var i = 0
        while i < scalars.count {
            let ch = scalars[i]
            if ch == "." {
                let nextIsDigit = i + 1 < scalars.count && scalars[i + 1].isNumber
                if nextIsDigit {
                    current.append(ch)
                } else {
                    parts.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
            i += 1
        }
        parts.append(current)
        return parts
    }
}
