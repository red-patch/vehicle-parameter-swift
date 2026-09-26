import Foundation

// MARK: - 智能填报域逻辑（旧版 matcher.ts + MatchResultTable 域侧语义直译）

/// 单条匹配填报项（旧版 MatchItem）
public struct MatchItem: Identifiable, Hashable, Sendable {
    /// 需求文本行索引（"req-0" 形式，与旧版一致）
    public var id: String
    /// 需求参数名（原始输入行）
    public var requirementName: String
    /// 匹配到的库参数（未匹配为 nil）
    public var matchedParam: VehicleParameter?
    /// 置信度 0-1（exact 1.0 / normalized 0.95 / alias 0.9 / fuzzy 1-score）
    public var confidence: Double
    /// 用户手动改过值（含显式空值）
    public var isManual: Bool
    /// 手动输入的值（优先于自动匹配值导出）
    public var manualValue: String?

    public init(
        id: String, requirementName: String, matchedParam: VehicleParameter?,
        confidence: Double, isManual: Bool = false, manualValue: String? = nil
    ) {
        self.id = id
        self.requirementName = requirementName
        self.matchedParam = matchedParam
        self.confidence = confidence
        self.isManual = isManual
        self.manualValue = manualValue
    }

    /// 当前生效值：手动值优先，其次自动匹配值
    public var effectiveValue: String {
        if let manualValue { return manualValue }
        return matchedParam?.displayValue ?? ""
    }

    /// 填报状态：已匹配（自动/手动有值）/ 未填报
    public var isFilled: Bool {
        matchedParam != nil || manualValue != nil
    }
}

public enum SmartFiller {
    /// 需求文本 → 匹配项列表（旧版 SmartFillView 输入即触发逻辑的域侧版本）
    /// 需求文本按行拆分、trim、滤空行；默认阈值 0.4
    public static func match(
        requirementsText: String, library: [VehicleParameter], threshold: Double = 0.4
    ) -> [MatchItem] {
        let requirements = requirementsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return findMatches(requirements, library: library, threshold: threshold)
    }

    /// 需求名列表 → 匹配项（旧版 matcher.ts findMatches 直译）
    public static func findMatches(
        _ requirements: [String], library: [VehicleParameter], threshold: Double = 0.4
    ) -> [MatchItem] {
        let index = CandidateIndex(library, threshold: threshold)
        return requirements.enumerated().map { reqIndex, reqName in
            let matchResult = findBestMatch(reqName, in: index, threshold: threshold)

            var confidence = 0.0
            if matchResult.matchedParam != nil {
                switch matchResult.matchType {
                case .exact: confidence = 1.0
                case .normalized: confidence = 0.95
                case .alias: confidence = 0.9
                case .fuzzy: confidence = max(0, 1 - matchResult.score)
                case .none: confidence = 0
                }
            }

            return MatchItem(
                id: "req-\(reqIndex)",
                requirementName: reqName,
                matchedParam: matchResult.matchedParam,
                confidence: (confidence * 100).rounded() / 100
            )
        }
    }

    /// 更新手动值（旧版 updateManualValue 语义：显式空值固化 ""，不回退自动值）
    public static func updateManualValue(_ item: MatchItem, _ value: String?) -> MatchItem {
        var updated = item
        if let value {
            updated.manualValue = value
            updated.isManual = true
        } else {
            updated.manualValue = nil
            updated.isManual = false
        }
        return updated
    }

    /// 快捷修正推荐（旧版 quickFixes：Fuse threshold 0.6 无扩展搜索，
    /// 排除当前匹配项，取前 3 的 name+value）
    public static func quickFixes(
        for item: MatchItem, library: [VehicleParameter], limit: Int = 3
    ) -> [(title: String, value: String)] {
        guard library.isEmpty == false else { return [] }
        guard item.confidence < 1.0 else { return [] }

        var options = FuseOptions()
        options.threshold = 0.6
        options.ignoreLocation = true  // 旧版 quickFix 未开 useExtendedSearch
        let engine = FuseEngine(texts: library.map(\.name), options: options)
        let results = engine.search(item.requirementName).prefix(4)
        return results
            .map { library[$0.index] }
            .filter { $0.name != item.matchedParam?.name }
            .prefix(limit)
            .map { (title: $0.name, value: $0.displayValue) }
    }

    /// 枚举异常检测：有枚举字典且当前值不在枚举列表
    public static func isEnumMismatch(
        _ item: MatchItem, dictionary: EnumDictionary
    ) -> Bool {
        let value = item.effectiveValue
        guard !value.isEmpty else { return false }
        let enums = dictionary.enumValues(for: item.requirementName)
        return !enums.isEmpty && !enums.contains(value)
    }

    /// 车上云模板导出行数据（[["参数项名称","参数值"], ...]，与旧版一致）
    public static func vehicleCloudRows(_ items: [MatchItem]) -> [[String]] {
        [["参数项名称", "参数值"]]
            + items.map { [$0.requirementName, $0.effectiveValue] }
    }
}

// MARK: - 产品置信度（旧版 productConfidence.ts 直译）

public struct ProductConfidence: Sendable, Equatable {
    public enum Level: String, Sendable {
        case high, medium, low
    }

    public let name: String
    public let confidence: Int  // 0-100
    public let paramCount: Int
    public let level: Level
    public let reason: String?
}

public enum ProductConfidenceEvaluator {
    static let blacklist = [
        "单选", "多选", "文本", "数值", "数值，无小数", "必填", "选填",
        "提供", "可提供", "不提供", "A类要求", "B类要求", "状态确认",
        "/", "—", "-", "无", "N/A", "n/a", "暂无", "待定",
    ]
    static let suspiciousKeywords = ["要求", "说明", "备注", "类型", "状态", "确认", "附件", "资料"]
    /// 正面特征正则（与旧版 PRODUCT_POSITIVE_PATTERNS 一致）
    static let positivePatterns = [
        "[A-Z]{2,}",
        "[A-Za-z]+\\d+",
        "(?i)\\d+kWh",
        "\\d+[mM][mM]",
        "栏板|厢货|客运|货运|高顶|长轴|短轴",
        "宁德|比亚迪|国轩|蜂巢",
    ]

    public static func evaluate(productName: String, paramCount: Int) -> ProductConfidence {
        var score = 0
        var reason = ""
        let name = productName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 黑名单（命中直接 0 分）
        if blacklist.contains(where: { name == $0 || name.lowercased() == $0.lowercased() }) {
            return ProductConfidence(name: name, confidence: 0, paramCount: paramCount,
                                     level: .low, reason: "匹配黑名单关键词")
        }

        // 2. 参数数量评分（40%）
        var paramScore = 0
        if paramCount >= 100 { paramScore = 40 }
        else if paramCount >= 50 { paramScore = 30 }
        else if paramCount >= 20 { paramScore = 20 }
        else if paramCount >= 5 { paramScore = 10 }
        else {
            paramScore = 0
            reason = "参数数量过少(\(paramCount))"
        }
        score += paramScore

        // 3. 名称特征评分（35%）
        var nameScore = 0
        let positiveMatches = positivePatterns.filter { captureRegex(name, pattern: $0) != nil }.count
        if positiveMatches >= 2 {
            nameScore = 35
        } else if positiveMatches == 1 {
            nameScore = 25
        } else {
            let hasCJK = name.unicodeScalars.contains { (0x4E00...0x9FA5).contains($0.value) }
            let hasAlnum = name.unicodeScalars.contains { $0.properties.isAlphabetic || ($0.value >= 48 && $0.value <= 57) }
            if name.utf16.count > 10, hasCJK, hasAlnum {
                nameScore = 20
            } else if name.utf16.count <= 4, hasCJK, !hasAlnum {
                nameScore = 5
                if reason.isEmpty { reason = "名称过短且为纯中文" }
            } else {
                nameScore = 15
            }
        }
        if suspiciousKeywords.contains(where: name.contains) {
            nameScore = max(0, nameScore - 10)
            if reason.isEmpty { reason = "包含可疑关键词" }
        }
        score += nameScore

        let level: ProductConfidence.Level = score >= 60 ? .high : (score >= 35 ? .medium : .low)
        return ProductConfidence(
            name: name, confidence: score, paramCount: paramCount,
            level: level, reason: level == .low ? reason : nil
        )
    }

    /// 批量评估并排序（等级 → 置信度降序）
    public static func evaluateAll(_ products: [(name: String, paramCount: Int)]) -> [ProductConfidence] {
        products.map { evaluate(productName: $0.name, paramCount: $0.paramCount) }
            .sorted { a, b in
                let order: [ProductConfidence.Level: Int] = [.high: 0, .medium: 1, .low: 2]
                if order[a.level] != order[b.level] {
                    return order[a.level]! < order[b.level]!
                }
                return a.confidence > b.confidence
            }
    }
}
