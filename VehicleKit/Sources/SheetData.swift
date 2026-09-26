import Foundation

/// 单文件解析结果（对应旧版 SheetData）
public struct SheetData: Sendable, Equatable, Codable {
    public var fileName: String
    public var data: [VehicleParameter]
    public var rawHeaders: [String]

    public init(fileName: String, data: [VehicleParameter], rawHeaders: [String] = []) {
        self.fileName = fileName
        self.data = data
        self.rawHeaders = rawHeaders
    }
}
