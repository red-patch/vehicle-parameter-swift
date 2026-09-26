import XCTest
@testable import VehicleKit

/// M4：净化规则 / 属性去重 / 公告查询导入
final class DataToolsTests: XCTestCase {
    // MARK: Purifier

    private var purifier: Purifier {
        Purifier(dictionary: EnumDictionary.loadBundled())
    }

    func testNameStandardAndFixes() {
        let params = [
            VehicleParameter(id: "1", group: "g", name: "360环视", value: .string("标配")),   // 字典内 → 标准
            VehicleParameter(id: "2", group: "g", name: "360度环视系统", value: .string("无")), // 非标准 → 推荐前3
            VehicleParameter(id: "3", group: "g", name: "", value: .string("")),               // 空名 = 非标准（旧版语义）
        ]
        let result = purifier.purify(params)
        XCTAssertTrue(result[0].isNameStandard)
        XCTAssertFalse(result[1].isNameStandard)
        XCTAssertLessThanOrEqual(result[1].nameFixes.count, 3)
        XCTAssertFalse(result[1].nameFixes.isEmpty, "「360度环视系统」应能推荐「360环视」")
        XCTAssertFalse(result[2].isNameStandard, "空名称按旧版 isKnownAttributeName 判非标准")
        XCTAssertTrue(result[2].nameFixes.isEmpty, "空名跳过推荐计算")
        XCTAssertEqual(purifier.anomalyCount(in: result), 2)
    }

    func testEnumMismatchCaseInsensitive() {
        let params = [
            VehicleParameter(id: "1", group: "g", name: "360环视", value: .string("标配")),
            VehicleParameter(id: "2", group: "g", name: "360环视", value: .string("带实时监控")),  // 枚举外值
            VehicleParameter(id: "3", group: "g", name: "360环视", value: .string("标配 ")),  // 尾空格 trim 后匹配
            VehicleParameter(id: "4", group: "g", name: "360环视", value: .string("")),
        ]
        let result = purifier.purify(params)
        XCTAssertTrue(result[0].hasEnums && !result[0].isEnumMismatch)
        XCTAssertTrue(result[1].isEnumMismatch)
        XCTAssertFalse(result[2].isEnumMismatch, "trim 后应在枚举内")
        XCTAssertFalse(result[3].isEnumMismatch, "空值不算值异常")
    }

    func testAnomalyCountAndRoundTrip() {
        let params = [
            VehicleParameter(id: "1", group: "g", name: "360环视", value: .string("标配")),
            VehicleParameter(id: "2", group: "g", name: "非标准字段名", value: .string("x")),
        ]
        let result = purifier.purify(params)
        XCTAssertEqual(purifier.anomalyCount(in: result), 1)
        // 回转 VehicleParameter 保留字段
        let back = Purifier.toParameters(result)
        XCTAssertEqual(back[0].id, "1")
        XCTAssertEqual(back[0].group, "g")
        XCTAssertEqual(back[0].displayValue, "标配")
    }

    func testFieldGroupsLoad() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fg_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // 无配置 → 默认两组
        XCTAssertEqual(FieldGroups.load(directory: dir).count, 2)
        // custom_fields.json groups 优先
        let config = #"{"groups":[{"id":"a","name":"A组","fields":["字段1"," 字段1 ",""]}],"systemRequired":["X"]}"#
        try Data(config.utf8).write(to: dir.appendingPathComponent("custom_fields.json"))
        let groups = FieldGroups.load(directory: dir)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, "a")
        XCTAssertEqual(groups[0].fields, ["字段1"])
        // systemRequired/qualityCheck 形态
        let config2 = #"{"systemRequired":["字段1","字段2"],"qualityCheck":["字段3"]}"#
        try Data(config2.utf8).write(to: dir.appendingPathComponent("custom_fields.json"))
        let groups2 = FieldGroups.load(directory: dir)
        XCTAssertEqual(groups2[0].id, "system-required")
        XCTAssertEqual(groups2[0].fields, ["字段1", "字段2"])
        XCTAssertEqual(groups2[1].fields, ["字段3"])
    }

    // MARK: AttributeDedup

    func testAttributeDedupParity() throws {
        let rows = try AttributeDedup.dedupe(url: Golden.url("attribute_pool.xlsx"))
        // 7 个非空名称（含重复 2 组）→ 去重后 5
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.name), ["驱动形式", "轴距(mm)", "车身长度", "最高车速(km/h)", "轮胎规格"])
        XCTAssertEqual(rows[0].required, "是", "首见 required 保留（重复行的「否」被忽略）")
        XCTAssertEqual(rows[1].required, "是")
        XCTAssertEqual(rows[2].required, "否")
        XCTAssertEqual(rows[0].id, 0)
        XCTAssertEqual(rows[4].id, 4)
    }

    func testAttributeDedupCSVEscaping() {
        let rows = [
            AttributeRow(id: 0, name: "带\"引号\"的字段", required: "是"),
            AttributeRow(id: 1, name: "普通", required: "否"),
        ]
        let csv = AttributeDedup.csvContent(rows)
        XCTAssertEqual(csv, "属性名称,是否必填\n\"带\"\"引号\"\"的字段\",\"是\"\n\"普通\",\"否\"")
        XCTAssertEqual(AttributeDedup.outputFileName(for: "属性池2025.xlsx"), "属性池2025_去重.csv")
        XCTAssertEqual(AttributeDedup.outputFileName(for: "属性池.XLS"), "属性池_去重.csv")
    }

    // MARK: AnnouncementQuery

    func testQueryURLBuilding() throws {
        let url = try XCTUnwrap(AnnouncementQuery.queryURL(for: "JHC6507BEVR2"))
        XCTAssertEqual(url.absoluteString,
                       "https://service.miit-eidc.org.cn/miitxxgk/gonggao/xxgk/index?querylb=cp&querydata=JHC6507BEVR2")
        // 中文/特殊字符 percent-encode
        let cn = try XCTUnwrap(AnnouncementQuery.queryURL(for: "产品 号"))
        XCTAssertTrue(cn.query!.contains("%"))
    }

    func testImportNormalFields() throws {
        let json = #"{"source":"miit-helper","parameters":[{"name":"车辆型号","value":"DNC5037","group":"工信部数据"},{"name":"总质量","value":"4495"}]}"#
        let sheet = try AnnouncementQuery.parseImport(json, announcementNo: "JHC6507")
        XCTAssertEqual(sheet.fileName, "JHC6507")
        XCTAssertEqual(sheet.rawHeaders, ["参数名", "值"])
        XCTAssertEqual(sheet.data.count, 2)
        XCTAssertEqual(sheet.data[0].name, "车辆型号")
        XCTAssertEqual(sheet.data[0].group, "工信部数据")
        XCTAssertEqual(sheet.data[1].group, "基础信息", "缺省 group 回退")
        XCTAssertEqual(sheet.data[1].originSheet, "工信部官网")
    }

    func testImportOtherFieldSplitting() throws {
        let json = #"{"source":"miit-helper","parameters":[{"name":"其它","value":"1.底盘:东风牌;2.发动机:玉柴YC4F;铁壳油箱.选装;3.5L 排量"}]}"#
        let sheet = try AnnouncementQuery.parseImport(json)
        let names = sheet.data.map(\.name)
        // 原始字段保留 + 子字段拆分
        XCTAssertEqual(sheet.data.first?.id, "miit-0-origin")
        XCTAssertTrue(names.contains("底盘"))
        XCTAssertTrue(names.contains("发动机"))
        // "铁壳油箱.选装"（点号后非数字）为分隔点 → 简单文本路径，名称 其它-N
        XCTAssertTrue(names.contains { $0.hasPrefix("其它-") })
        // "3.5L 排量" 中的小数点不被切分（点号后跟数字）
        let joined = sheet.data.map(\.displayValue).joined()
        XCTAssertTrue(joined.contains("3.5L 排量"), "小数点不得切分：\(joined)")
        XCTAssertTrue(sheet.data.filter { $0.group == "其它-详细参数" }.count >= 3)
    }

    func testImportRejectsBadPayload() {
        XCTAssertThrowsError(try AnnouncementQuery.parseImport("not json")) { error in
            XCTAssertEqual((error as? AnnouncementQuery.ImportError)?.errorDescription, "解析JSON失败，请检查粘贴内容")
        }
        XCTAssertThrowsError(try AnnouncementQuery.parseImport(#"{"source":"other","parameters":[]}"#)) { error in
            XCTAssertEqual((error as? AnnouncementQuery.ImportError)?.errorDescription, "数据格式不正确，请确保复制的是书签脚本生成的数据")
        }
    }

    func testBookmarkletParity() {
        // 书签脚本与旧版逐字符一致（互通契约）
        XCTAssertTrue(AnnouncementQuery.bookmarkletCode.hasPrefix("javascript:(function(){try{const table=document.querySelector('table.query_result_table')"))
        XCTAssertTrue(AnnouncementQuery.bookmarkletCode.contains("miit-helper"))
    }
}
