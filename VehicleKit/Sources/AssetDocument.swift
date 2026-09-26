import Foundation

/// 资产文件格式 v1.0 —— 与旧版 `assetManager.ts` 的 `AssetFileFormat` 互通。
///
/// 契约：旧版导出的 JSON 必须可无损读入；本版导出必须写回同格式，
/// 保证新旧版资产库目录可互用（见 README「数据兼容」）。
public struct AssetDocument: Codable, Hashable, Sendable {
    public static let formatVersion = "1.0"

    public var version: String
    public var productName: String
    /// ISO8601 时间戳，按旧版 `new Date().toISOString()` 的字符串原样保存
    public var createdAt: String
    public var updatedAt: String
    public var parameters: [VehicleParameter]

    public init(
        version: String = AssetDocument.formatVersion,
        productName: String,
        createdAt: String,
        updatedAt: String,
        parameters: [VehicleParameter]
    ) {
        self.version = version
        self.productName = productName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parameters = parameters
    }

    /// 新建文档时的时间戳（毫秒精度，与旧版 toISOString 一致）
    public static func nowTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}

extension AssetDocument {
    /// 以旧版磁盘格式（2 空格缩进）解码资产文件
    public static func decode(from data: Data) throws -> AssetDocument {
        let decoder = JSONDecoder()
        return try decoder.decode(AssetDocument.self, from: data)
    }

    /// 编码为 JSON（2 空格缩进）。
    /// 注意：语义与旧版互通无损；但 Xcode 16 的 JSONEncoder 空白风格（`"key" : value`）与
    /// 字段序和 JSON.stringify 不逐字节一致。旧版 JSON.parse 读回不受影响；
    /// 若 M3 golden 测试要求逐字节对齐，再实现专用 legacy writer。
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try encoder.encode(self)
    }
}
