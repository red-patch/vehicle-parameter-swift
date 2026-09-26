import Foundation

// MARK: - 资产库目录存取（旧版 assetManager.ts 直译）
//
// 目录契约（与旧版 Tauri 版互通，可直接挂载旧版资产目录）：
//   *.json            —— 资产数据文件（AssetDocument v1.0 格式）
//   _asset_tags.json  —— 标签映射 Record<fileName, string[]>
//   custom_asset_tag_groups.json —— 标签分组配置
//   custom_enums.json —— 枚举字典覆写（M2 EnumDictionary 消费）
// 以 `_` 开头的任意文件是元数据，`custom_` 前缀是配置，均不算资产数据。

public struct AssetFileInfo: Sendable, Equatable, Identifiable {
    public var id: String { fileName }
    public let fileName: String
    public let productName: String
    public let updatedAt: String?
    public let totalParams: Int
    public let filledParams: Int
    /// 公告号列表（公告号/产品号/产品ID 等字段中的纯字母数字值）
    public let announceNos: [String]
    /// 车辆型号（公告数据源以此为公告号）
    public let vehicleModel: String?
}

public struct AssetTagGroup: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let tags: [String]

    public init(id: String, name: String, tags: [String]) {
        self.id = id
        self.name = name
        self.tags = tags
    }
}

public struct AssetTagGroupsConfig: Sendable, Equatable, Codable {
    public var groups: [AssetTagGroup]
    public var exclusiveGroups: [String]

    public static let `default` = AssetTagGroupsConfig(groups: [], exclusiveGroups: [])

    public init(groups: [AssetTagGroup] = [], exclusiveGroups: [String] = []) {
        self.groups = groups
        self.exclusiveGroups = exclusiveGroups
    }
}

public enum AssetStoreError: Error, LocalizedError {
    case notFound(String)
    case invalidName(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let f): "资产文件不存在：\(f)"
        case .invalidName(let f): "非法文件名：\(f)"
        }
    }
}

public struct AssetStore {
    public let directory: URL

    /// 数据资产文件判定（排除元数据/配置），与旧版 isAssetDataFile 一致
    public static func isAssetDataFile(_ name: String) -> Bool {
        name.hasSuffix(".json") && !name.hasPrefix("_") && !name.hasPrefix("custom_")
    }

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: 扫描

    /// 遍历资产目录，轻量解析并统计核心元信息（旧版 getAssetFilesWithInfo）
    public func scan() -> [AssetFileInfo] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var results: [AssetFileInfo] = []
        for url in entries where Self.isAssetDataFile(url.lastPathComponent) {
            if let info = Self.inspect(url: url, fileName: url.lastPathComponent) {
                results.append(info)
            }
        }
        results.sort { $0.fileName < $1.fileName }
        return results
    }

    /// 单文件解析统计（供增量刷新复用）
    public static func inspect(url: URL, fileName: String) -> AssetFileInfo? {
        guard let data = try? Data(contentsOf: url),
              let doc = try? AssetDocument.decode(from: data) else {
            return nil
        }
        let params = doc.parameters
        let filled = params.filter { !$0.displayValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count

        // 公告号提取：仅纯字母数字（过滤复合 ID）
        let announceNameKeys = ["公告号", "产品号", "产品ID", "公告产品号", "产品编号"]
        var announceNos: [String] = []
        for p in params where announceNameKeys.contains(where: { p.name == $0 || p.name.contains($0) }) {
            let value = p.displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let pure = !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
                (scalar.value >= 48 && scalar.value <= 57)      // 0-9
                    || (scalar.value >= 65 && scalar.value <= 90)   // A-Z
                    || (scalar.value >= 97 && scalar.value <= 122)  // a-z
            }
            if pure, !announceNos.contains(value) {
                announceNos.append(value)
            }
        }

        let vehicleModel = params.first { $0.name == "车辆型号" }
            .map { $0.displayValue.trimmingCharacters(in: .whitespacesAndNewlines) }

        return AssetFileInfo(
            fileName: fileName,
            productName: doc.productName.isEmpty
                ? fileName.replacingOccurrences(of: "\\.json$", with: "", options: [.regularExpression, .caseInsensitive])
                : doc.productName,
            updatedAt: doc.updatedAt.isEmpty ? doc.createdAt : doc.updatedAt,
            totalParams: params.count,
            filledParams: filled,
            announceNos: announceNos,
            vehicleModel: (vehicleModel?.isEmpty ?? true) ? nil : vehicleModel
        )
    }

    // MARK: 读 / 写

    /// 加载资产为 SheetData（rawHeaders 与旧版 loadAssetFile 一致）
    public func load(fileName: String) throws -> SheetData {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let doc = try? AssetDocument.decode(from: data) else {
            throw AssetStoreError.notFound(fileName)
        }
        let assetProductName = doc.productName.isEmpty
            ? fileName.replacingOccurrences(of: "\\.json$", with: "", options: [.regularExpression, .caseInsensitive])
            : doc.productName
        let normalized = doc.parameters.map { p in
            var param = p
            if param.productName == nil || param.productName!.isEmpty {
                param.productName = assetProductName
            }
            return param
        }
        return SheetData(fileName: fileName, data: normalized, rawHeaders: ["参数分组", "参数名称", "参数值"])
    }

    /// 以 v1.0 格式写出资产文件（互通契约；返回最终路径）
    @discardableResult
    public func save(fileName: String, productName: String, parameters: [VehicleParameter],
                     createdAt: String? = nil) throws -> URL {
        guard !fileName.isEmpty, !fileName.contains("/") else {
            throw AssetStoreError.invalidName(fileName)
        }
        let finalName = fileName.hasSuffix(".json") ? fileName : "\(fileName).json"
        let now = AssetDocument.nowTimestamp()
        let doc = AssetDocument(
            productName: productName,
            createdAt: createdAt ?? now,
            updatedAt: now,
            parameters: parameters
        )
        let url = directory.appendingPathComponent(finalName)
        try doc.encoded().write(to: url)
        return url
    }

    public func delete(fileName: String) throws {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AssetStoreError.notFound(fileName)
        }
        try FileManager.default.removeItem(at: url)
    }

    public func rename(oldFileName: String, newFileName: String) throws -> String {
        let normalize = { (name: String) in name.hasSuffix(".json") ? name : "\(name).json" }
        let finalOld = normalize(oldFileName)
        let finalNew = normalize(newFileName)
        let oldURL = directory.appendingPathComponent(finalOld)
        let newURL = directory.appendingPathComponent(finalNew)
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            throw AssetStoreError.notFound(finalOld)
        }
        if oldURL != newURL {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            // 标签映射同步改名
            var tags = loadTags()
            if let oldTags = tags.removeValue(forKey: finalOld) {
                tags[finalNew] = oldTags
                try saveTags(tags)
            }
        }
        return finalNew
    }

    // MARK: 标签映射（_asset_tags.json）

    public var tagsURL: URL { directory.appendingPathComponent("_asset_tags.json") }

    public func loadTags() -> [String: [String]] {
        guard let data = try? Data(contentsOf: tagsURL),
              let tags = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }
        return tags
    }

    public func saveTags(_ tags: [String: [String]]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(tags).write(to: tagsURL)
    }

    public func setTags(fileName: String, _ fileTags: [String]) throws {
        var tags = loadTags()
        if fileTags.isEmpty {
            tags.removeValue(forKey: fileName)
        } else {
            tags[fileName] = fileTags
        }
        try saveTags(tags)
    }

    // MARK: 标签分组配置（custom_asset_tag_groups.json）

    public var tagGroupsURL: URL { directory.appendingPathComponent("custom_asset_tag_groups.json") }

    public func loadTagGroups() -> AssetTagGroupsConfig {
        guard let data = try? Data(contentsOf: tagGroupsURL),
              let config = try? JSONDecoder().decode(AssetTagGroupsConfig.self, from: data) else {
            return .default
        }
        return config
    }

    public func saveTagGroups(_ config: AssetTagGroupsConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(config).write(to: tagGroupsURL)
    }

    /// 单组内标签去重（保留首次出现序、去空白）——旧版 normalizeTagList
    public static func normalizeTagList(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            result.append(t)
        }
        return result
    }
}
