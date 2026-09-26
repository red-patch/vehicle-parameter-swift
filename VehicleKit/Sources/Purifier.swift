import Foundation

// MARK: - 数据净化（旧版 DataPurifyView 域侧语义直译）
//
// 三个检测维度：名称标准性（枚举字典内）、名称推荐（Fuse 0.6 搜标准字段）、
// 枚举值不匹配（大小写不敏感比较——与 SmartFiller 的精确比较不同，旧版两模块如此）。

public struct PurifiedParam: Identifiable, Hashable, Sendable {
    public var id: String
    public var group: String
    public var name: String
    public var value: String
    public var productName: String?
    public var originSheet: String?
    public var updatedAt: String?

    /// 名称是否在枚举字典中（标准字段）
    public var isNameStandard: Bool
    /// 非标准名称的推荐标准字段（前 3）
    public var nameFixes: [String]
    /// 该字段可用的枚举值
    public var enums: [String]
    public var hasEnums: Bool
    /// 值不在枚举字典（大小写不敏感）
    public var isEnumMismatch: Bool

    /// 异常 = 名称不标准 或 值不在枚举（空值不算值异常）
    public var isAnomaly: Bool { !isNameStandard || isEnumMismatch }
}

public struct Purifier {
    /// 枚举字典（同时充当标准字段名集合）
    public let dictionary: EnumDictionary
    /// 标准字段名的 Fuse 索引（threshold 0.6，与旧版 standardFieldsFuse 一致）
    private let fieldsFuse: FuseEngine

    public init(dictionary: EnumDictionary) {
        self.dictionary = dictionary
        var options = FuseOptions()
        options.threshold = 0.6
        // 旧版 new Fuse(fields.map(f => ({name: f})), {keys:['name'], threshold: 0.6})
        // 未开 ignoreLocation/useExtendedSearch——保持默认
        self.fieldsFuse = FuseEngine(texts: dictionary.allAttributeNames, options: options)
    }

    /// 参数列表 → 净化增强列表（旧版 augmentedParams）
    public func purify(_ params: [VehicleParameter]) -> [PurifiedParam] {
        params.map { p in
            // isNameStandard 直接取字典判定（空名 = 非标准，计入异常）；
            // nameFixes 对空名跳过（旧版 isKnownAttributeName || !name.trim() 前置短路）
            let isNameStandard = dictionary.isKnownAttributeName(p.name)
            var fixes: [String] = []
            if !isNameStandard, !p.name.trimmingCharacters(in: .whitespaces).isEmpty {
                fixes = fieldsFuse.search(p.name).prefix(3).map { dictionary.allAttributeNames[$0.index] }
            }
            let enums = p.name.isEmpty ? [] : dictionary.enumValues(for: p.name)
            let strValue = p.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let isEnumMismatch = !enums.isEmpty && !strValue.isEmpty
                && !enums.contains { $0.lowercased() == strValue.lowercased() }
            return PurifiedParam(
                id: p.id, group: p.group, name: p.name, value: p.displayValue,
                productName: p.productName, originSheet: p.originSheet, updatedAt: p.updatedAt,
                isNameStandard: isNameStandard, nameFixes: fixes,
                enums: enums, hasEnums: !enums.isEmpty, isEnumMismatch: isEnumMismatch
            )
        }
    }

    /// 异常计数
    public func anomalyCount(in params: [PurifiedParam]) -> Int {
        params.filter(\.isAnomaly).count
    }

    /// 净化结果 → 资产保存参数（PurifiedParam 回到 VehicleParameter）
    public static func toParameters(_ params: [PurifiedParam]) -> [VehicleParameter] {
        params.map { p in
            VehicleParameter(
                id: p.id, group: p.group, name: p.name, value: .string(p.value),
                originSheet: p.originSheet, productName: p.productName,
                updatedAt: p.updatedAt
            )
        }
    }

    /// 更新行时间戳格式（旧版：MM-dd HH:mm 本地时区）
    public static func nowStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

// MARK: - 字段组配置（旧版 fieldLists.ts：custom_fields.json 热替换）

public struct FieldGroupConfig: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let fields: [String]

    public init(id: String, name: String, fields: [String]) {
        self.id = id
        self.name = name
        self.fields = fields
    }
}

public enum FieldGroups {
    public static let defaultGroups = [
        FieldGroupConfig(id: "system-required", name: "系统必填字段", fields: []),
        FieldGroupConfig(id: "quality-check", name: "质量验车字段", fields: []),
    ]

    /// custom_fields.json 结构（与旧版 CustomFieldsConfig 一致）
    private struct CustomFieldsConfig: Codable {
        var groups: [FieldGroupConfig]?
        var systemRequired: [String]?
        var qualityCheck: [String]?
    }

    /// 从资产目录加载字段组（custom_fields.json 优先；无配置时回退默认）
    public static func load(directory: URL?) -> [FieldGroupConfig] {
        guard let directory else { return defaultGroups }
        let url = directory.appendingPathComponent("custom_fields.json")
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(CustomFieldsConfig.self, from: data) else {
            return defaultGroups
        }
        // 去重但保持插入序（旧版 JS Set 语义；Swift Set 顺序随机不可用）
        let normalize = { (fields: [String]) in
            var seen = Set<String>()
            var result: [String] = []
            for f in fields {
                let trimmed = f.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
                seen.insert(trimmed)
                result.append(trimmed)
            }
            return result
        }
        if let groups = config.groups, !groups.isEmpty {
            return groups
                .map { FieldGroupConfig(id: $0.id.trimmingCharacters(in: .whitespaces),
                                        name: $0.name.trimmingCharacters(in: .whitespaces),
                                        fields: normalize($0.fields)) }
                .filter { !$0.id.isEmpty && !$0.name.isEmpty }
        }
        return [
            FieldGroupConfig(id: "system-required", name: "系统必填字段", fields: normalize(config.systemRequired ?? [])),
            FieldGroupConfig(id: "quality-check", name: "质量验车字段", fields: normalize(config.qualityCheck ?? [])),
        ]
    }
}
