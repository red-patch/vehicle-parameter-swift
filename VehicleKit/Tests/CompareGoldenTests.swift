import XCTest
@testable import VehicleKit

/// 对比器四态结果与旧版 golden 的逐项对齐测试（M1 核心验收）
final class CompareGoldenTests: XCTestCase {
    private static let golden: [String: GoldenCompareEntry] = {
        try! JSONDecoder().decode([String: GoldenCompareEntry].self, from: Golden.loadJSON("compare_golden"))
    }()

    private func runPair(base: String, target: String, key: String, mode: CompareMode) throws {
        let baseSheet = try ExcelParser.parse(url: Golden.url(base))
        let targetSheet = try ExcelParser.parse(url: Golden.url(target))
        let result = compareSheets(baseSheet, targetSheet, mode: mode)

        guard let expected = Self.golden[key] else {
            return XCTFail("golden 缺少 key：\(key)")
        }
        XCTAssertEqual(result.added.count, expected.counts.added, "\(key) added 计数不一致")
        XCTAssertEqual(result.removed.count, expected.counts.removed, "\(key) removed 计数不一致")
        XCTAssertEqual(result.modified.count, expected.counts.modified, "\(key) modified 计数不一致")
        XCTAssertEqual(result.unchanged.count, expected.counts.unchanged, "\(key) unchanged 计数不一致")

        assertParametersMatch(result.added, expected.added)
        assertParametersMatch(result.removed, expected.removed)
        assertParametersMatch(result.unchanged, expected.unchanged)
        if result.modified.count == expected.modified.count {
            for (i, (a, e)) in zip(result.modified, expected.modified).enumerated() {
                if a.id != e.id || a.oldParam.name != e.old.name || a.oldParam.displayValue != e.old.value
                    || a.newParam.name != e.new.name || a.newParam.displayValue != e.new.value {
                    XCTFail("""
                    \(key) 第 \(i) 个 modified 不一致：
                      Swift : id=\(a.id) old=\(a.oldParam.name):\(a.oldParam.displayValue) new=\(a.newParam.name):\(a.newParam.displayValue)
                      golden: id=\(e.id) old=\(e.old.name):\(e.old.value) new=\(e.new.name):\(e.new.value)
                    """)
                }
            }
        }
    }

    func testDitieContentParity() throws {
        try runPair(base: "02-地上铁需求参数反馈（02月03日版本）.xlsx", target: "02-地上铁需求参数反馈（9月25日版本）.xlsx", key: "ditie_content", mode: .content)
    }

    func testDitieMiitParity() throws {
        try runPair(base: "02-地上铁需求参数反馈（02月03日版本）.xlsx", target: "02-地上铁需求参数反馈（9月25日版本）.xlsx", key: "ditie_miit", mode: .miit)
    }

    func testDemoContentParity() throws {
        try runPair(base: "demo.xlsx", target: "demo_new.xlsx", key: "demo_content", mode: .content)
    }

    func testDemoMiitParity() throws {
        try runPair(base: "demo.xlsx", target: "demo_new.xlsx", key: "demo_miit", mode: .miit)
    }

    func testHorizontalContentParity() throws {
        try runPair(base: "old.xlsx", target: "new.xlsx", key: "horizontal_content", mode: .content)
    }

    func testHorizontalMiitParity() throws {
        try runPair(base: "old.xlsx", target: "new.xlsx", key: "horizontal_miit", mode: .miit)
    }

    // MARK: - 语义单元用例

    func testModifiedDetectionByValueDifference() {
        let base = SheetData(fileName: "b", data: [
            VehicleParameter(id: "b::p::g::整备质量", group: "g", name: "整备质量", value: .string("1780")),
        ])
        let target = SheetData(fileName: "t", data: [
            VehicleParameter(id: "t::p::g::整备质量", group: "g", name: "整备质量", value: .string("1820")),
            VehicleParameter(id: "t::p::g::最高车速", group: "g", name: "最高车速", value: .string("100")),
        ])
        let result = compareSheets(base, target)
        XCTAssertEqual(result.modified.count, 1)
        XCTAssertEqual(result.modified.first?.oldParam.displayValue, "1780")
        XCTAssertEqual(result.modified.first?.newParam.displayValue, "1820")
        XCTAssertEqual(result.added.count, 1)
        XCTAssertEqual(result.unchanged.count, 0)
    }

    func testFuzzyMatchingBridgesUnitSuffix() {
        // 基准"轴距(mm)" vs 对比"轴距"：normalized 归一后相等 → unchanged
        let base = SheetData(fileName: "b", data: [
            VehicleParameter(id: "b1", group: "g", name: "轴距(mm)", value: .string("2900")),
        ])
        let target = SheetData(fileName: "t", data: [
            VehicleParameter(id: "t1", group: "g", name: "轴距", value: .string("2900")),
        ])
        let result = compareSheets(base, target)
        XCTAssertEqual(result.removed.count, 0, "轴距(mm) 应经归一化匹配而非判 removed")
        XCTAssertEqual(result.added.count, 0)
        XCTAssertEqual(result.unchanged.count, 1)
    }

    func testMiitModeIgnoresBaseExtras() {
        // miit：以 Target 为基准，Base 多余字段不出现在 removed
        let base = SheetData(fileName: "b", data: [
            VehicleParameter(id: "b1", group: "g", name: "整备质量", value: .string("1780")),
            VehicleParameter(id: "b2", group: "g", name: "内部备注", value: .string("x")),
        ])
        let target = SheetData(fileName: "t", data: [
            VehicleParameter(id: "t1", group: "g", name: "整备质量", value: .string("1780")),
        ])
        let result = compareSheets(base, target, mode: .miit)
        XCTAssertEqual(result.removed.count, 0)
        XCTAssertEqual(result.unchanged.count, 1)
    }

    func testDuplicateNameLastValueWins() {
        // JS Map 语义：同名参数后者覆盖前者
        let base = SheetData(fileName: "b", data: [
            VehicleParameter(id: "b1", group: "g", name: "轴距", value: .string("2900")),
            VehicleParameter(id: "b2", group: "g", name: "轴距", value: .string("3100")),
        ])
        let target = SheetData(fileName: "t", data: [
            VehicleParameter(id: "t1", group: "g", name: "轴距", value: .string("3100")),
        ])
        let result = compareSheets(base, target)
        XCTAssertEqual(result.unchanged.count, 1, "同名后值（3100）应参与比较")
        XCTAssertEqual(result.modified.count, 0)
    }
}
