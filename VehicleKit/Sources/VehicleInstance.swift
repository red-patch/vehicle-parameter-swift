import Foundation

// MARK: - 车型实例 key 语义（旧版 vehicleInstance.ts 直译）
//
// key 形如 `source::fileName::productName`，是数据池中车型的唯一标识。
// 与旧版对齐的语义：来源区分（excel/asset）、显示标签去重、排序规则。

public enum VehicleSource: String, Sendable, CaseIterable {
    case excel
    case asset
}

public struct VehicleInstanceMeta: Sendable, Equatable {
    public let source: VehicleSource
    public let fileName: String
    public let productName: String
    public let key: String
}

public struct VehicleDisplayLabel: Sendable, Equatable {
    /// 下拉里的短标签（同名重名时带 （N） 序号）
    public let shortLabel: String
    /// 完整标签（`productName · fileName`，同名时省略）
    public let fullLabel: String
}

public enum VehicleInstance {
    static let separator = "::"

    public static func buildKey(source: VehicleSource, fileName: String, productName: String) -> String {
        "\(source.rawValue)\(separator)\(fileName)\(separator)\(productName)"
    }

    /// 解析实例 key；非法来源或空段返回 nil（与旧版一致）
    public static func parse(_ value: String) -> VehicleInstanceMeta? {
        guard let firstSep = value.range(of: separator) else { return nil }
        let afterFirst = value.index(firstSep.upperBound, offsetBy: 0)
        guard let secondSep = value.range(of: separator, range: afterFirst..<value.endIndex) else { return nil }

        let sourceRaw = String(value[value.startIndex..<firstSep.lowerBound])
        guard let source = VehicleSource(rawValue: sourceRaw) else { return nil }

        let fileName = String(value[firstSep.upperBound..<secondSep.lowerBound])
        let productName = String(value[secondSep.upperBound...])
        if fileName.isEmpty || productName.isEmpty { return nil }

        return VehicleInstanceMeta(source: source, fileName: fileName, productName: productName, key: value)
    }

    public static func productName(of value: String) -> String {
        parse(value)?.productName ?? value
    }

    public static func sourceFileName(of value: String) -> String? {
        parse(value)?.fileName
    }

    public static func meta(source: VehicleSource, fileName: String, productName: String) -> VehicleInstanceMeta {
        VehicleInstanceMeta(
            source: source, fileName: fileName, productName: productName,
            key: buildKey(source: source, fileName: fileName, productName: productName)
        )
    }

    /// 从参数与来源文件推导实例元数据：优先用参数上已有的 instanceKey
    public static func metaFromParam(
        source: VehicleSource, fileFileName: String, param: VehicleParameter
    ) -> VehicleInstanceMeta {
        if let existing = param.instanceKey.flatMap(parse(_:)) {
            return existing
        }
        let productName = param.productName ?? fileFileName
        return meta(source: source, fileName: fileFileName, productName: productName)
    }

    public static func optionLabel(_ instanceKey: String) -> String {
        guard let parsed = parse(instanceKey) else { return instanceKey }
        // 同名时只显示产品名，避免重复显示（如"新石器_X3 · 新石器_X3.json"）
        let fileNameBase = parsed.fileName.replacingOccurrences(
            of: "\\.json$", with: "", options: [.regularExpression, .caseInsensitive])
        if parsed.productName == fileNameBase { return parsed.productName }
        return "\(parsed.productName) · \(parsed.fileName)"
    }

    // MARK: 排序与显示标签

    /// localeCompare('zh-Hans-CN', {numeric: true, sensitivity: 'base'}) 等价比较
    static func zhCompare(_ left: String, _ right: String) -> Bool  // 返回 left < right
    {
        let result = left.compare(
            right, options: [.numeric, .caseInsensitive],
            range: nil, locale: Locale(identifier: "zh-Hans-CN"))
        return result == .orderedAscending
    }

    static func compareMeta(_ left: VehicleInstanceMeta, _ right: VehicleInstanceMeta) -> Bool  // left 在前
    {
        if left.fileName != right.fileName {
            return zhCompare(left.fileName, right.fileName)
        }
        // asset 在 excel 前
        let leftOrder = left.source == .asset ? 0 : 1
        let rightOrder = right.source == .asset ? 0 : 1
        if leftOrder != rightOrder { return leftOrder < rightOrder }
        return zhCompare(left.key, right.key)
    }

    /// 批量构建显示标签：同产品名按排序规则编号（1）（2）…，其余单实例直接用产品名
    public static func displayLabels(for instanceKeys: [String]) -> [String: VehicleDisplayLabel] {
        var labels: [String: VehicleDisplayLabel] = [:]
        var metas = Array(Set(instanceKeys)).compactMap(parse(_:))

        var grouped: [String: [VehicleInstanceMeta]] = [:]
        for meta in metas {
            grouped[meta.productName, default: []].append(meta)
        }

        for (_, group) in grouped {
            let sorted = group.sorted { compareMeta($0, $1) }
            for (index, meta) in sorted.enumerated() {
                labels[meta.key] = VehicleDisplayLabel(
                    shortLabel: sorted.count > 1 ? "\(meta.productName)（\(index + 1)）" : meta.productName,
                    fullLabel: optionLabel(meta.key)
                )
            }
        }

        for key in instanceKeys where labels[key] == nil {
            labels[key] = VehicleDisplayLabel(
                shortLabel: productName(of: key),
                fullLabel: optionLabel(key)
            )
        }
        return labels
    }

    /// 选择匹配：key 全等或产品名相等（旧版 matchesVehicleSelection）
    public static func matchesSelection(_ selection: String, instanceKey: String) -> Bool {
        if selection == instanceKey { return true }
        return productName(of: selection) == productName(of: instanceKey)
    }
}
