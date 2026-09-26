import Foundation

// MARK: - 对比器（旧版 comparator.ts 直译）
//
// 语义要点：
// - 以 name 为键建 Map：键的首次出现序保留、值取最后一次写入（JS Map 语义）
// - content 模式：精确 → 模糊（阈值 0.4，防多对一）→ 四态归类
// - miit 模式：以 Target 为基准遍历，Base 缺失视为新增需求，Base 多余忽略

public enum CompareMode: String, Sendable {
    case content
    case miit
}

public struct ModifiedParameter: Sendable, Equatable {
    public let id: String
    public let oldParam: VehicleParameter
    public let newParam: VehicleParameter
}

public struct DiffResult: Sendable, Equatable {
    public var added: [VehicleParameter] = []
    public var removed: [VehicleParameter] = []
    public var modified: [ModifiedParameter] = []
    public var unchanged: [VehicleParameter] = []

    public init() {}

    public var total: Int { added.count + removed.count + modified.count + unchanged.count }
}

/// 有序参数表：键序 = 首次插入序；值 = 最后写入（JS Map 语义）
private struct OrderedParamMap {
    private var order: [String] = []
    private var map: [String: VehicleParameter] = [:]

    init(_ params: [VehicleParameter]) {
        for p in params {
            if map[p.name] == nil { order.append(p.name) }
            map[p.name] = p
        }
    }

    subscript(name: String) -> VehicleParameter? { map[name] }

    var names: [String] { order }

    var entries: [(name: String, param: VehicleParameter)] {
        order.compactMap { name in map[name].map { (name, $0) } }
    }
}

/// 对比两个 Sheet 数据
/// - Parameter mode: `content` 按内容对比（默认）；`miit` 仅公告号数据对比
public func compareSheets(
    _ base: SheetData, _ target: SheetData, mode: CompareMode = .content
) -> DiffResult {
    mode == .miit ? compareByMiit(base: base, target: target) : compareByContent(base: base, target: target)
}

/// 按字段内容对比（支持模糊匹配）
/// 匹配优先级：精确匹配 > 清洗匹配 > 同义词匹配 > 模糊匹配
private func compareByContent(base: SheetData, target: SheetData) -> DiffResult {
    let baseMap = OrderedParamMap(base.data)
    let targetMap = OrderedParamMap(target.data)

    var added: [VehicleParameter] = []
    var removed: [VehicleParameter] = []
    var modified: [ModifiedParameter] = []
    var unchanged: [VehicleParameter] = []

    var matchedTargetKeys = Set<String>()
    var finalMatches: [String: VehicleParameter] = [:]  // baseName -> targetParam

    // Step 1: 精确匹配优先
    for baseName in baseMap.names {
        if let targetParam = targetMap[baseName] {
            finalMatches[baseName] = targetParam
            matchedTargetKeys.insert(baseName)
        }
    }

    // Step 2: 模糊匹配剩余项（候选列表固定一份；usedTargetNames 防多对一）
    let unmatchedTargetCandidates: [VehicleParameter] = targetMap.names.compactMap { name in
        matchedTargetKeys.contains(name) ? nil : targetMap[name]
    }
    let unmatchedIndex = CandidateIndex(unmatchedTargetCandidates, threshold: 0.4)
    var usedTargetNames = Set<String>(matchedTargetKeys)

    for baseName in baseMap.names where finalMatches[baseName] == nil {
        let matchResult = findBestMatch(baseName, in: unmatchedIndex, threshold: 0.4)
        if let matched = matchResult.matchedParam, !usedTargetNames.contains(matched.name) {
            finalMatches[baseName] = matched
            matchedTargetKeys.insert(matched.name)
            usedTargetNames.insert(matched.name)
        }
    }

    // Step 3: 生成结果
    for (baseName, baseParam) in baseMap.entries {
        if let targetParam = finalMatches[baseName] {
            if baseParam.displayValue != targetParam.displayValue {
                modified.append(ModifiedParameter(id: baseParam.id, oldParam: baseParam, newParam: targetParam))
            } else {
                unchanged.append(baseParam)
            }
        } else {
            removed.append(baseParam)
        }
    }

    // Step 4: 收集新增项
    for targetName in targetMap.names where !matchedTargetKeys.contains(targetName) {
        if let targetParam = targetMap[targetName] {
            added.append(targetParam)
        }
    }

    var result = DiffResult()
    result.added = added
    result.removed = removed
    result.modified = modified
    result.unchanged = unchanged
    return result
}

/// 按公告数据对比（以 Target 为基准，Base 中多余的字段忽略）
/// 适用于：Target=工信部数据，Base=用户上传文件
private func compareByMiit(base: SheetData, target: SheetData) -> DiffResult {
    let baseParams = base.data  // 全量作为候选
    let baseMap = OrderedParamMap(base.data)
    let targetMap = OrderedParamMap(target.data)

    var added: [VehicleParameter] = []
    var removed: [VehicleParameter] = []
    var modified: [ModifiedParameter] = []
    var unchanged: [VehicleParameter] = []

    let baseIndex = CandidateIndex(baseParams, threshold: 0.4)

    for targetName in targetMap.names {
        guard let targetParam = targetMap[targetName] else { continue }
        var baseParam: VehicleParameter?

        // 1. 精确匹配（Map：同名后值优先）
        if let exact = baseMap[targetName] {
            baseParam = exact
        } else {
            // 2. 模糊匹配（统一引擎）
            baseParam = findBestMatch(targetName, in: baseIndex, threshold: 0.4).matchedParam
        }

        if let baseParam {
            if baseParam.displayValue != targetParam.displayValue {
                modified.append(ModifiedParameter(id: baseParam.id, oldParam: baseParam, newParam: targetParam))
            } else {
                unchanged.append(baseParam)
            }
        } else {
            // 用户数据中缺失该工信部字段 -> 视为新增需求
            added.append(targetParam)
        }
    }

    var result = DiffResult()
    result.added = added
    result.removed = removed
    result.modified = modified
    result.unchanged = unchanged
    return result
}
