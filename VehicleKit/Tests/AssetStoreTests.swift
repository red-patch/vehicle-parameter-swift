import XCTest
@testable import VehicleKit

/// M3：资产库目录存取 + SQLite 持久化（导入导出往返无损验收）
final class AssetStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: AssetStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("asset_store_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = AssetStore(directory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private let sampleParams: [VehicleParameter] = [
        VehicleParameter(id: "整备质量", group: "车身", name: "整备质量", value: .number(1780),
                         originSheet: "整车参数", productName: "DNC5037"),
        VehicleParameter(id: "续航", group: "动力", name: "CLTC续航里程", value: .string("560km"),
                         originSheet: "整车参数", productName: "DNC5037"),
        VehicleParameter(id: "空值", group: "车身", name: "备注", value: .string(""),
                         originSheet: "整车参数", productName: "DNC5037"),
    ]

    // MARK: 目录扫描与读回

    func testSaveScanLoadRoundTrip() throws {
        try store.save(fileName: "DNC5037.json", productName: "DNC5037", parameters: sampleParams)
        try store.save(fileName: "V6E.json", productName: "V6E 客运版", parameters: Array(sampleParams.prefix(2)))

        // 扫描统计
        let infos = store.scan()
        XCTAssertEqual(infos.count, 2)
        XCTAssertEqual(infos.map(\.fileName).sorted(), ["DNC5037.json", "V6E.json"])
        let dnc = infos.first { $0.fileName == "DNC5037.json" }!
        XCTAssertEqual(dnc.totalParams, 3)
        XCTAssertEqual(dnc.filledParams, 2, "空值参数不计入已填")
        XCTAssertEqual(dnc.productName, "DNC5037")
        XCTAssertNotNil(dnc.updatedAt)

        // 读回无损（语义级）
        let sheet = try store.load(fileName: "DNC5037.json")
        XCTAssertEqual(sheet.data.count, 3)
        XCTAssertEqual(sheet.rawHeaders, ["参数分组", "参数名称", "参数值"])
        XCTAssertEqual(sheet.data[0].value, .number(1780))
        XCTAssertEqual(sheet.data[1].value, .string("560km"))
        XCTAssertNil(sheet.data[1].productName == "DNC5037" ? nil : sheet.data[1].productName)
        // productName 缺省补齐
        let bare = sampleParams[0]
        _ = bare
        let loadedNames = Set(sheet.data.compactMap(\.productName))
        XCTAssertEqual(loadedNames, ["DNC5037"])
    }

    func testScanSkipsMetadataAndConfigFiles() throws {
        try store.save(fileName: "a.json", productName: "A", parameters: sampleParams)
        // 元数据与配置文件（_ 前缀 / custom_ 前缀）
        try store.saveTags(["a.json": ["标签1"]])
        try store.saveTagGroups(.default)
        let enumsJSON = Data(#"{"字段": ["值1"]}"#.utf8)
        try enumsJSON.write(to: tempDir.appendingPathComponent("custom_enums.json"))

        XCTAssertEqual(store.scan().count, 1, "只统计数据资产文件")
        XCTAssertTrue(AssetStore.isAssetDataFile("x.json"))
        XCTAssertFalse(AssetStore.isAssetDataFile("_asset_tags.json"))
        XCTAssertFalse(AssetStore.isAssetDataFile("custom_enums.json"))
    }

    func testAnnounceAndVehicleModelExtraction() throws {
        let params: [VehicleParameter] = [
            VehicleParameter(id: "1", group: "g", name: "公告号", value: .string("JHC6507BEVR2")),
            VehicleParameter(id: "2", group: "g", name: "产品ID", value: .string("V7E50kwh_20260303-JHC6507BEVR2")),  // 复合 ID 过滤
            VehicleParameter(id: "3", group: "g", name: "车辆型号", value: .string("DNC5037XXYBEVP1")),
        ]
        try store.save(fileName: "m.json", productName: "M", parameters: params)
        let info = store.scan().first!
        XCTAssertEqual(info.announceNos, ["JHC6507BEVR2"])
        XCTAssertEqual(info.vehicleModel, "DNC5037XXYBEVP1")
    }

    // MARK: 标签映射与分组配置

    func testTagsPersistAndClear() throws {
        try store.setTags(fileName: "a.json", ["新能源", "48V"])
        XCTAssertEqual(store.loadTags(), ["a.json": ["新能源", "48V"]])
        // 空标签删除映射
        try store.setTags(fileName: "a.json", [])
        XCTAssertEqual(store.loadTags(), [:])
    }

    func testTagGroupsConfig() throws {
        var config = AssetTagGroupsConfig.default
        config.groups = [AssetTagGroup(id: "g1", name: "用途", tags: [" 客运 ", "货运", "客运"])]
        try store.saveTagGroups(config)
        let loaded = store.loadTagGroups()
        XCTAssertEqual(loaded.groups.count, 1)
        // 配置文件按写入原样保存；归一化（normalizeTagList）在展示层做
        XCTAssertEqual(loaded.groups[0].tags, [" 客运 ", "货运", "客运"])
        XCTAssertEqual(AssetStore.normalizeTagList([" 客运 ", "货运", "客运", ""]), ["客运", "货运"])
    }

    // MARK: 重命名/删除

    func testRenameSyncsTags() throws {
        try store.save(fileName: "old.json", productName: "OLD", parameters: sampleParams)
        try store.setTags(fileName: "old.json", ["保留"])
        let newName = try store.rename(oldFileName: "old.json", newFileName: "new")
        XCTAssertEqual(newName, "new.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("old.json").path))
        XCTAssertEqual(store.loadTags()["new.json"], ["保留"])
        XCTAssertThrowsError(try store.rename(oldFileName: "ghost.json", newFileName: "x.json"))
    }

    // MARK: GRDB 持久化

    func testDatabaseUpsertQueryTags() throws {
        let db = try AssetDatabase()
        try store.save(fileName: "a.json", productName: "A", parameters: sampleParams)

        // 目录 → 库
        let infos = store.scan()
        let records: [(AssetFileInfo, Data)] = try infos.map { info in
            let doc = try AssetDocument.decode(from: Data(contentsOf: tempDir.appendingPathComponent(info.fileName)))
            return (info, try JSONEncoder().encode(doc.parameters))
        }
        try db.upsertAssets(records)

        XCTAssertEqual(try db.allAssets().count, 1)
        let record = try db.asset(fileName: "a.json")
        XCTAssertEqual(record?.productName, "A")
        XCTAssertEqual(record?.parameters.count, try JSONEncoder().encode(sampleParams).count)

        // upsert 幂等（重复扫描不重复插入）
        try db.upsertAssets(records)
        XCTAssertEqual(try db.allAssets().count, 1)

        // 标签
        try db.setTags(fileName: "a.json", ["b", "a", "b"])
        XCTAssertEqual(try db.tagsForAsset(fileName: "a.json"), ["a", "b"])
        try db.setTags(fileName: "a.json", ["c"])
        XCTAssertEqual(try db.tagsForAsset(fileName: "a.json"), ["c"])
        XCTAssertEqual(try db.allTags(), ["a.json": ["c"]])

        // 删除级联清标签
        try db.deleteAsset(fileName: "a.json")
        XCTAssertEqual(try db.allTags(), [:])
    }

    func testSessionRoundTrip() throws {
        let db = try AssetDatabase()
        let payload = try JSONEncoder().encode([SheetData(fileName: "f.xlsx", data: sampleParams)])
        try db.saveSession(SessionRecord(
            key: "current", uploadedFiles: payload, selectedProducts: nil,
            confirmed: nil, excluded: nil, ignored: nil, updatedAt: nil))
        let loaded = try db.session()
        XCTAssertEqual(loaded?.uploadedFiles, payload)
        XCTAssertNotNil(loaded?.updatedAt)
    }

    // MARK: 旧版真实格式兼容

    func testLegacyDirectoryMount() throws {
        // 构造与旧版一致的手写资产文件（含 createdAt/updatedAt 与嵌套可选字段缺省）
        let legacy = """
        {
          "version": "1.0",
          "productName": "V6E 33l类",
          "createdAt": "2025-03-01T09:30:00.000Z",
          "updatedAt": "2025-06-15T14:20:11.123Z",
          "parameters": [
            {"id": "整备质量", "group": "车身", "name": "整备质量", "value": 1780}
          ]
        }
        """
        try Data(legacy.utf8).write(to: tempDir.appendingPathComponent("V6E 33l类.json"))
        let info = store.scan().first
        XCTAssertEqual(info?.productName, "V6E 33l类")
        XCTAssertEqual(info?.updatedAt, "2025-06-15T14:20:11.123Z")

        // 读回 → 再写出 → 再读回，逐参数语义无损（互通契约）。
        // 注意 load() 会按旧版 loadAssetFile 语义回填缺失的 productName
        let sheet = try store.load(fileName: "V6E 33l类.json")
        try store.save(fileName: "回写.json", productName: sheet.data.first!.productName!,
                       parameters: sheet.data, createdAt: "2025-03-01T09:30:00.000Z")
        let doc = try AssetDocument.decode(
            from: Data(contentsOf: tempDir.appendingPathComponent("回写.json")))
        XCTAssertEqual(doc.version, "1.0")
        XCTAssertEqual(doc.createdAt, "2025-03-01T09:30:00.000Z", "createdAt 保留原值")
        XCTAssertEqual(doc.parameters.first?.value, .number(1780))
        XCTAssertEqual(doc.parameters.first?.productName, "V6E 33l类", "回填字段随写出保留")
    }
}
