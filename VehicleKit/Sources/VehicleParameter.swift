import Foundation

/// 整车参数 —— 与旧版 `src/types/index.ts` 的 `VehicleParameter` 逐字段对齐。
///
/// 这是资产 JSON 兼容契约（version 1.0）的核心实体：字段增删需保证新旧版双向兼容。
public struct VehicleParameter: Codable, Hashable, Sendable {
    /// 唯一标识，通常是参数名或参数名+分组
    public var id: String
    /// 分组/类别
    public var group: String
    /// 参数名
    public var name: String
    /// 参数值（旧版为 string | number 双态）
    public var value: ParameterValue
    /// 行是否需要核对（保留原字段概念）
    public var rowCheck: String?
    /// 来源 Sheet 页名称
    public var originSheet: String?
    /// 产品名称（列头）
    public var productName: String?
    /// 车型实例唯一键：source::fileName::productName
    public var instanceKey: String?
    /// 参数修改的最后时间记录戳（V5.4 追加）
    public var updatedAt: String?

    public init(
        id: String,
        group: String,
        name: String,
        value: ParameterValue,
        rowCheck: String? = nil,
        originSheet: String? = nil,
        productName: String? = nil,
        instanceKey: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.group = group
        self.name = name
        self.value = value
        self.rowCheck = rowCheck
        self.originSheet = originSheet
        self.productName = productName
        self.instanceKey = instanceKey
        self.updatedAt = updatedAt
    }

    /// 用于展示的值文本
    public var displayValue: String { value.displayText }
}

/// 旧版 `value: string | number` 的双态桥接。
///
/// 编码规则保持 JSON 原生类型：字符串编为字符串；数字在整数值域内编码为整数
/// （不带 `.0`，与旧版 `JSON.stringify` 输出一致）。
public enum ParameterValue: Hashable, Sendable {
    case string(String)
    case number(Double)

    /// 整数按整数还原输出，避免 123 → "123.0" 的漂移
    public var displayText: String {
        switch self {
        case .string(let text): text
        case .number(let value):
            if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
                String(Int64(value))
            } else {
                String(value)
            }
        }
    }
}

extension ParameterValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case string, number
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if container.decodeNil() {
            // 旧数据中可能存在 null 值，按空串收容
            self = .string("")
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "VehicleParameter.value 既不是字符串也不是数字"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text):
            try container.encode(text)
        case .number(let value):
            if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        }
    }
}

extension ParameterValue: CustomStringConvertible {
    public var description: String { displayText }
}

extension VehicleParameter {
    /// 供 UI 展示的稳定标识（M3 车型实例 key 语义会扩展此处）
    public var displayName: String {
        group.isEmpty ? name : "\(group) / \(name)"
    }
}
