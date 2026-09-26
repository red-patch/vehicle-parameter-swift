import Foundation

// MARK: - 属性枚举值字典（旧版 attributeEnums.ts 直译）
//
// 数据源：内置 attribute_values.txt（与旧版 src/assets 同源，"属性名称,属性值列表"
// CSV，值以 | 分隔）；支持 custom_enums.json（JSON 字典）覆写对应键集。

/// 枚举字典（线程安全：加载后只读）
public final class EnumDictionary: @unchecked Sendable {
    /// 原始字段名 → 枚举值列表（插入序保留）
    private var cache: [String: [String]] = [:]
    /// 标准化名 → 原始名
    private var normalizedNameMap: [String: String] = [:]

    public init() {}

    /// 属性名称标准化：去空格、中文括号转英文、小写
    static func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .lowercased()
    }

    /// 从内置 CSV 加载（应用启动/测试入口）
    public static func loadBundled() -> EnumDictionary {
        let dict = EnumDictionary()
        guard let url = Bundle.module.url(forResource: "attribute_values", withExtension: "txt", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return dict
        }
        dict.applyCsv(text)
        return dict
    }

    /// 解析 CSV 文本并入缓存（旧版 applyCsvToCache 语义：首行表头、BOM 清除、HTML 污染防护）
    @discardableResult
    public func applyCsv(_ csvText: String) -> Int {
        var text = csvText
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let headSample = String(text.prefix(200)).lowercased()
        if headSample.contains("<html") || headSample.contains("<head") || headSample.contains("<body") {
            return 0
        }

        var loaded = 0
        let lines = text.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let fields = Self.parseCsvLine(trimmed)
            guard fields.count >= 1 else { continue }
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let valuesStr = fields.count > 1 ? fields[1] : ""
            let values = valuesStr.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            normalizedNameMap[Self.normalizeName(name)] = name
            cache[name] = values
            loaded += 1
        }
        return loaded
    }

    /// 覆写自定义字典（custom_enums.json）；HTML 污染防护与旧版一致
    @discardableResult
    public func applyCustomEnums(_ config: [String: [String]]) -> Int {
        let keys = Array(config.keys)
        guard !keys.isEmpty else { return 0 }
        let suspicious = keys.filter { captureRegex($0, pattern: "<[^>]+>") != nil }
        if Double(suspicious.count) / Double(keys.count) > 0.2 {
            return 0
        }
        var overwritten = 0
        for (key, values) in config {
            let name = key.trimmingCharacters(in: .whitespaces)
            normalizedNameMap[Self.normalizeName(name)] = name
            cache[name] = values
            overwritten += 1
        }
        return overwritten
    }

    /// 属性的枚举值列表（标准化名查找），无枚举返回空数组
    public func enumValues(for attributeName: String) -> [String] {
        if let direct = cache[attributeName] { return direct }
        guard let original = normalizedNameMap[Self.normalizeName(attributeName)] else { return [] }
        return cache[original] ?? []
    }

    public func hasEnumValues(for attributeName: String) -> Bool {
        !enumValues(for: attributeName).isEmpty
    }

    public var allAttributeNames: [String] { Array(cache.keys) }
    public var count: Int { cache.count }

    /// CSV 行解析（引号包裹处理，与旧版 parseCSVLine 一致）
    static func parseCsvLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ",", !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}
