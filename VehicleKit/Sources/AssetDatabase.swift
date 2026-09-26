import Foundation
import GRDB

// MARK: - 资产库 SQLite 持久化（架构蓝图 §3 schema，GRDB）
//
// 目录扫描（AssetStore）是事实来源；本库是加速缓存 + 标签/会话的结构化存储。
// 启动时从目录 upsert 进 SQLite；导出时以目录 JSON 为准写回 v1.0 格式。

public struct AssetRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var id: Int64?
    public var fileName: String
    public var productName: String
    public var createdAt: String?
    public var updatedAt: String?
    /// VehicleParameter[] 的 JSON 编码
    public var parameters: Data

    public static let databaseTableName = "assets"

    enum CodingKeys: String, CodingKey {
        case id, fileName = "file_name", productName = "product_name"
        case createdAt = "created_at", updatedAt = "updated_at", parameters
    }
}

public struct AssetTagRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var assetId: Int64
    public var tag: String
    public var groupId: String

    public static let databaseTableName = "asset_tags"

    enum CodingKeys: String, CodingKey {
        case assetId = "asset_id", tag, groupId = "group_id"
    }
}

public struct SessionRecord: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var key: String
    public var uploadedFiles: Data?
    public var selectedProducts: Data?
    public var confirmed: Data?
    public var excluded: Data?
    public var ignored: Data?
    public var updatedAt: String?

    public static let databaseTableName = "sessions"

    enum CodingKeys: String, CodingKey {
        case key
        case uploadedFiles = "uploaded_files"
        case selectedProducts = "selected_products"
        case confirmed, excluded, ignored
        case updatedAt = "updated_at"
    }
}

public final class AssetDatabase: Sendable {
    private let dbWriter: any DatabaseWriter

    public init(path: String) throws {
        dbWriter = try DatabasePool(path: path)
        try migrator.migrate(dbWriter)
    }

    /// 内存库（测试用）
    public init() throws {
        dbWriter = try DatabaseQueue()
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("m3") { db in
            try db.create(table: "assets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("file_name", .text).notNull().unique()
                t.column("product_name", .text).notNull()
                t.column("created_at", .text)
                t.column("updated_at", .text)
                t.column("parameters", .blob)
            }
            try db.create(table: "asset_tags") { t in
                t.column("asset_id", .integer).references("assets", onDelete: .cascade)
                t.column("tag", .text).notNull()
                t.column("group_id", .text).notNull().defaults(to: "default")
                t.primaryKey(["asset_id", "tag"])
            }
            try db.create(table: "sessions") { t in
                t.primaryKey("key", .text)
                t.column("uploaded_files", .blob)
                t.column("selected_products", .blob)
                t.column("confirmed", .blob)
                t.column("excluded", .blob)
                t.column("ignored", .blob)
                t.column("updated_at", .text)
            }
        }
        return migrator
    }

    // MARK: assets

    /// 目录扫描结果 → upsert（file_name 为唯一键）
    public func upsertAssets(_ records: [(info: AssetFileInfo, parameters: Data)]) throws {
        try dbWriter.write { db in
            for entry in records {
                let existing = try AssetRecord
                    .filter(Column("file_name") == entry.info.fileName)
                    .fetchOne(db)
                let record = AssetRecord(
                    id: existing?.id,
                    fileName: entry.info.fileName,
                    productName: entry.info.productName,
                    createdAt: existing?.createdAt ?? entry.info.updatedAt,
                    updatedAt: entry.info.updatedAt,
                    parameters: entry.parameters
                )
                try record.save(db)
            }
        }
    }

    public func allAssets() throws -> [AssetRecord] {
        try dbWriter.read { db in
            try AssetRecord.order(Column("file_name")).fetchAll(db)
        }
    }

    public func asset(fileName: String) throws -> AssetRecord? {
        try dbWriter.read { db in
            try AssetRecord.filter(Column("file_name") == fileName).fetchOne(db)
        }
    }

    public func deleteAsset(fileName: String) throws {
        _ = try dbWriter.write { db in
            try AssetRecord.filter(Column("file_name") == fileName).deleteAll(db)
        }
    }

    // MARK: asset_tags

    /// 设置某资产的全部标签（组内默认组；增量 diff 写库）
    public func setTags(fileName: String, _ tags: [String], groupId: String = "default") throws {
        try dbWriter.write { db in
            guard let asset = try AssetRecord
                .filter(Column("file_name") == fileName).fetchOne(db),
                let assetId = asset.id else {
                return
            }
            let existing = try AssetTagRecord
                .filter(Column("asset_id") == assetId && Column("group_id") == groupId)
                .fetchAll(db)
            let existingTags = Set(existing.map(\.tag))
            let target = Set(tags)
            for stale in existingTags.subtracting(target) {
                _ = try AssetTagRecord
                    .filter(Column("asset_id") == assetId && Column("tag") == stale && Column("group_id") == groupId)
                    .deleteAll(db)
            }
            for fresh in target.subtracting(existingTags) {
                try AssetTagRecord(assetId: assetId, tag: fresh, groupId: groupId).insert(db)
            }
        }
    }

    public func tagsForAsset(fileName: String) throws -> [String] {
        try dbWriter.read { db in
            let asset = try AssetRecord.filter(Column("file_name") == fileName).fetchOne(db)
            guard let assetId = asset?.id else { return [] }
            return try AssetTagRecord
                .filter(Column("asset_id") == assetId)
                .order(Column("tag"))
                .fetchAll(db)
                .map(\.tag)
        }
    }

    public func allTags() throws -> [String: [String]] {
        try dbWriter.read { db in
            let rows = try AssetTagRecord.fetchAll(db)
            var result: [String: [String]] = [:]
            let assets = try AssetRecord.fetchAll(db)
            let idToName = Dictionary(assets.compactMap { asset in
                asset.id.map { id in (id, asset.fileName) }
            }, uniquingKeysWith: { a, _ in a })
            for row in rows {
                guard let name = idToName[row.assetId] else { continue }
                result[name, default: []].append(row.tag)
            }
            return result
        }
    }

    // MARK: sessions

    public func saveSession(_ record: SessionRecord) throws {
        var record = record
        record.updatedAt = AssetDocument.nowTimestamp()
        try dbWriter.write { db in
            try record.save(db)
        }
    }

    public func session(key: String = "current") throws -> SessionRecord? {
        try dbWriter.read { db in
            try SessionRecord.filter(Column("key") == key).fetchOne(db)
        }
    }
}
