import Foundation

// MARK: - 参数匹配引擎（旧版 matchingEngine.ts 直译）
//
// 四级匹配语义是 golden 测试的契约，改动必须与旧版同步或说明理由：
//   exact      0
//   normalized 0.1
//   alias      0.1（标准词命中）/ 0.2（别名词命中）
//   fuzzy      ≤ threshold（bitap，经字段范数加权）
//   none       1

/// 归一化字段名：去除单位、括号、空格等干扰字符
/// e.g. "整备质量(kg)" -> "整备质量"
public func normalizeName(_ name: String) -> String {
    var result = name
    // 去除括号及内容（中英文括号可交叉配对，与旧版正则 [（(].*?[)）] 一致）
    result = replaceRegex(result, pattern: "[（(].*?[)）]", with: "")
    result = replaceRegex(result, pattern: "[\\[【].*?[\\]】]", with: "")
    result = replaceRegex(result, pattern: "\\s+", with: "")
    // 移除尾部常见单位（仅一次，锚定末尾，大小写不敏感）
    result = replaceRegex(result, pattern: "(?i)(mm|kg|km/h|kW|kWh|L)$", with: "")
    // ICU 正则的 \u 转义只支持四位十六进制形式
    result = replaceRegex(result, pattern: "[^\\u4e00-\\u9fa5a-zA-Z0-9]", with: "")
    return result.lowercased()
}

// replaceRegex 定义于 ExcelParser.swift（模块内共享）


// MARK: - 别名/同义词库（顺序即旧版对象字面量的插入序，属匹配语义的一部分）

public struct ParameterAliasGroup: Sendable {
    public let standard: String
    public let aliases: [String]
    public init(_ standard: String, _ aliases: [String]) {
        self.standard = standard
        self.aliases = aliases
    }
}

/// key: 标准名称（工信部常用名称）；value: 常见的其他叫法
public let parameterAliases: [ParameterAliasGroup] = [
    // --- 基础信息 ---
    .init("产品号", ["产品编号", "公告产品号"]),
    .init("产品ID", ["公告号id", "公告ID", "公告号ID"]),
    .init("批次", ["公告批次", "批次号"]),
    .init("发布日期", ["公告日期", "发布时间"]),
    .init("企业名称", ["整车生产企业", "主机厂", "生产厂家"]),
    .init("产品商标", ["品牌", "商标"]),
    .init("生产地址", ["生产厂地址", "厂址"]),
    .init("车辆型号", ["型号", "车型"]),
    .init("车辆名称", ["车型名称", "公告车型", "名称"]),
    .init("车辆识别代号(VIN)", ["VIN码前缀", "VIN", "VIN码"]),
    .init("是否免检", ["免征批次", "免检"]),
    .init("停产日期", ["状态", "停产状态"]),
    .init("停售日期", ["状态", "停售状态"]),
    // --- 尺寸类 ---
    .init("外形尺寸长", ["车长", "长度", "长", "整车长", "外廓长度(mm)", "外廓长度", "外廓尺寸长"]),
    .init("外形尺寸宽", ["车宽", "宽度", "宽", "整车宽", "外廓宽度(mm)", "外廓宽度", "外廓尺寸宽"]),
    .init("外形尺寸高", ["车高", "高度", "高", "整车高", "外廓高度(mm)", "外廓高度", "外廓尺寸高"]),
    .init("货厢长", ["货箱长", "箱长", "货箱长度", "内部长", "货厢内部长度", "货厢内部长度(mm)"]),
    .init("货厢宽", ["货箱宽", "箱宽", "货箱宽度", "内部宽", "货厢内部宽度", "货厢内部宽度(mm)"]),
    .init("货厢高", ["货箱高", "箱高", "货箱高度", "内部高", "货厢内部高度", "货厢内部高度(mm)"]),
    .init("轴距", ["前后轴距", "轴距(mm)"]),
    .init("轴数", ["车轴数", "轴数量"]),
    .init("前轮距", ["轮距(前)", "前轮距(mm)"]),
    .init("后轮距", ["轮距(后)", "后轮距(mm)"]),
    .init("前悬后悬", ["前/后悬(mm)", "前/后悬", "前悬/后悬"]),
    .init("接近角/离去角", ["接近角(°)/离去角(°)", "接近角/离去角", "接近离去角"]),
    // --- 质量类 ---
    .init("总质量", ["最大总质量", "满载质量", "总质量(kg)"]),
    .init("整备质量", ["自重", "空车重量", "整备质量(kg)"]),
    .init("额定载质量", ["载重量", "载重", "最大载质量", "额定载质量(kg)"]),
    .init("准拖挂车总质量", ["拖挂总质量", "准拖挂质量"]),
    .init("载质量利用系数", ["载质量系数", "利用系数"]),
    .init("半挂车鞍座最大允许载质量", ["鞍座载质量", "半挂鞍座载质量"]),
    .init("轴荷", ["前/后轴荷(kg)", "前/后轴荷", "轴荷分布"]),
    .init("驾驶室准乘人数", ["乘员数", "驾驶室人数", "准乘人数"]),
    .init("额定载客(含驾驶员)", ["乘员数", "载客人数", "额定载客"]),
    // --- 性能与动力 ---
    .init("最高车速", ["最高时速", "车速", "最大车速", "最高车速(km/h)"]),
    .init("发动机生产企业", ["电机厂商", "发动机企业", "动力企业"]),
    .init("发动机型号", ["电机型号", "动力型号"]),
    .init("发动机功率", ["功率", "最大功率", "电机功率", "额定功率", "电机额定功率(kW)"]),
    .init("排量", ["发动机排量"]),
    .init("燃料种类", ["燃料", "能源类型", "动力类型", "能源种类"]),
    .init("油耗", ["百公里油耗", "综合油耗"]),
    .init("排放依据标准", ["排放标准", "国六"]),
    .init("驱动电机对应关系", ["电机额定/峰值功率", "电机对应关系"]),
    .init("储能装置种类/生产企业", ["动力电池单体生产企业", "电池企业"]),
    .init("动力电池包电量", ["动力电池电量", "电量", "电池电量", "动力电池电量(kWh)", "动力电池包电量(kWh)"]),
    // --- 底盘与配置 ---
    .init("底盘ID", ["底盘编号"]),
    .init("底盘型号及企业", ["车身结构", "底盘型号"]),
    .init("钢板弹簧片数", ["板簧", "板簧数", "弹簧片数", "钢板弹簧"]),
    .init("轮胎数", ["轮胎数量"]),
    .init("轮胎规格", ["轮胎", "轮胎型号"]),
    .init("转向形式", ["转向助力类型", "转向类型"]),
    .init("防抱死系统", ["ABS"]),
    .init("ABS型号/生产企业", ["ABS系统型号/生产企业", "ABS型号"]),
    .init("反光标识企业", ["反光标识生产企业"]),
    .init("反光标识型号", ["反光标识"]),
    .init("反光标识商标", ["反光标识品牌"]),
    .init("其它", ["需求描述/备注", "备注", "其他"]),
]

// MARK: - 匹配结果

public enum MatchType: String, Sendable {
    case exact, normalized, alias, fuzzy, none
}

public struct MatchAlternative: Sendable {
    public let name: String
    public let value: String
    public let score: Double
}

public struct MatchResult: Sendable {
    public var matchedParam: VehicleParameter?
    /// 0-1，0 为完美匹配（Fuse 语义；置信度体系中 1 为完全可信）
    public var score: Double
    public var matchType: MatchType
    /// Top-N 模糊候选（排除最优项自身），供下拉修正 UI
    public var alternatives: [MatchAlternative]?

    static let noMatch = MatchResult(matchedParam: nil, score: 1, matchType: .none)
}

// MARK: - 候选索引

/// 对一组候选构建一次索引，供多次 findBestMatch 查询。
/// 对应旧版 WeakMap 缓存（同一 candidates 数组只建一次 normalized 索引与 Fuse 实例）。
public struct CandidateIndex {
    let candidates: [VehicleParameter]
    /// normalizeName -> 首个候选（旧版 map 首见不覆盖）
    let normalizedMap: [String: VehicleParameter]
    /// 旧版 Fuse.js 配置：keys ['name']、ignoreLocation、useExtendedSearch
    let fuse: FuseEngine

    public init(_ candidates: [VehicleParameter], threshold: Double = 0.3) {
        self.candidates = candidates
        var map: [String: VehicleParameter] = [:]
        for p in candidates where map[normalizeName(p.name)] == nil {
            map[normalizeName(p.name)] = p
        }
        self.normalizedMap = map
        var options = FuseOptions()
        options.threshold = threshold
        options.ignoreLocation = true
        options.useExtendedSearch = true
        self.fuse = FuseEngine(texts: candidates.map(\.name), options: options)
    }
}

// MARK: - 统一匹配入口

/// 统一匹配函数
/// - Parameters:
///   - queryName: 目标字段名（如用户输入的"车长"）
///   - index: 候选索引（同一候选组复用）
///   - threshold: 模糊匹配阈值 (0-1)，越小越严格，默认 0.3
public func findBestMatch(
    _ queryName: String,
    in index: CandidateIndex,
    threshold: Double = 0.3
) -> MatchResult {
    let candidates = index.candidates
    let normalizedQuery = normalizeName(queryName)

    // 1. 精确匹配（首个同名列）
    if let exactMatch = candidates.first(where: { $0.name == queryName }) {
        return MatchResult(matchedParam: exactMatch, score: 0, matchType: .exact)
    }

    // 2. 规范化匹配
    if let normalizedMatch = index.normalizedMap[normalizedQuery] {
        return MatchResult(matchedParam: normalizedMatch, score: 0.1, matchType: .normalized)
    }

    // 3. 同义词匹配（组序即声明序）
    for group in parameterAliases {
        let normalizedStandard = normalizeName(group.standard)
        let isQueryInGroup = normalizedQuery == normalizedStandard
            || group.aliases.contains { normalizeName($0) == normalizedQuery }
        guard isQueryInGroup else { continue }

        // 优先标准词
        if let standardCand = index.normalizedMap[normalizedStandard] {
            return MatchResult(matchedParam: standardCand, score: 0.1, matchType: .alias)
        }
        // 再按别名顺序
        for alias in group.aliases {
            if let aliasCand = index.normalizedMap[normalizeName(alias)] {
                return MatchResult(matchedParam: aliasCand, score: 0.2, matchType: .alias)
            }
        }
    }

    // 4. 模糊匹配
    let fuseResults = index.fuse.search(queryName)
    if let best = fuseResults.first, best.score <= threshold {
        let alternatives: [MatchAlternative] = fuseResults
            .dropFirst()
            .prefix(5)
            .filter { $0.score <= threshold }
            .map { r in
                MatchAlternative(
                    name: candidates[r.index].name,
                    value: candidates[r.index].displayValue,
                    score: r.score
                )
            }
        return MatchResult(
            matchedParam: candidates[best.index],
            score: best.score,
            matchType: .fuzzy,
            alternatives: alternatives.isEmpty ? nil : alternatives
        )
    }

    return .noMatch
}

/// 便捷入口：一次性匹配（不复用索引）
public func findBestMatch(
    _ queryName: String,
    candidates: [VehicleParameter],
    threshold: Double = 0.3
) -> MatchResult {
    findBestMatch(queryName, in: CandidateIndex(candidates, threshold: threshold), threshold: threshold)
}
