import XCTest
import CoreXLSX
@testable import VehicleKit

/// M2 智能填报：匹配结果 golden + 枚举字典 + 导出回读
final class SmartFillerGoldenTests: XCTestCase {
    struct SmartGolden: Codable {
        let requirementNames: [String]
        let libraryProductName: String
        let librarySize: Int
        let items: [Item]
        struct Item: Codable {
            let requirementName: String
            let matchedName: String?
            let matchedValue: String?
            let confidence: Double
        }
    }

    private static let golden: SmartGolden = {
        try! JSONDecoder().decode(SmartGolden.self, from: Golden.loadJSON("smartfill_golden"))
    }()

    private static let library: [VehicleParameter] = {
        // 从解析 golden 重建基准库（与 dump 脚本同口径：按产品过滤）
        let data = Golden.loadJSON("parse_golden")
        let entries = try! JSONDecoder().decode([String: GoldenParseEntry].self, from: data)
        let params = entries["02-地上铁需求参数反馈（02月03日版本）.xlsx"]!.parameters!
        return params
            .filter { $0.productName == golden.libraryProductName }
            .enumerated()
            .map { i, p in
                VehicleParameter(
                    id: p.id.isEmpty ? "lib\(i)" : p.id,
                    group: p.group, name: p.name, value: .string(p.value)
                )
            }
    }()

    /// findMatches 结果与旧版逐项一致（匹配目标 + 置信度）
    func testFindMatchesParity() {
        let results = SmartFiller.findMatches(Self.golden.requirementNames, library: Self.library)
        XCTAssertEqual(results.count, Self.golden.items.count)
        for (i, (actual, expected)) in zip(results, Self.golden.items).enumerated() {
            XCTAssertEqual(actual.requirementName, expected.requirementName, "第 \(i) 行需求名不一致")
            XCTAssertEqual(actual.matchedParam?.name, expected.matchedName,
                           "第 \(i) 行（\(expected.requirementName)）匹配目标不一致")
            XCTAssertEqual(actual.matchedParam?.displayValue, expected.matchedValue,
                           "第 \(i) 行（\(expected.requirementName)）匹配值不一致")
            assertClose(actual.confidence, expected.confidence,
                        "第 \(i) 行（\(expected.requirementName)）置信度不一致：\(actual.confidence) vs \(expected.confidence)")
        }
    }

    /// 需求文本入口（按行拆分、滤空行）语义；库内名为"整备质量（kg）"，
    /// 去括号归一后命中 → normalized 0.95（与 golden 一致）
    func testMatchFromRequirementsText() {
        let text = "\n  整备质量  \n\n最高车速\n   \n"
        let results = SmartFiller.match(requirementsText: text, library: Self.library)
        XCTAssertEqual(results.map(\.requirementName), ["整备质量", "最高车速"])
        XCTAssertEqual(results[0].confidence, 0.95)
        XCTAssertEqual(results[0].matchedParam?.name, "整备质量（kg）")
    }

    /// 手动值优先级与显式空值
    func testManualValuePriority() {
        var item = SmartFiller.findMatches(["整备质量"], library: Self.library)[0]
        XCTAssertEqual(item.effectiveValue, item.matchedParam?.displayValue)
        item = SmartFiller.updateManualValue(item, "1799")
        XCTAssertEqual(item.effectiveValue, "1799")
        XCTAssertTrue(item.isManual)
        item = SmartFiller.updateManualValue(item, "")
        XCTAssertEqual(item.effectiveValue, "", "显式空值不应回退自动值")
        item = SmartFiller.updateManualValue(item, nil)
        XCTAssertFalse(item.isManual)
        XCTAssertEqual(item.effectiveValue, item.matchedParam?.displayValue)
    }

    /// quickFix 语义：低置信度才给推荐、排除当前匹配项、前 3
    func testQuickFixes() {
        let items = SmartFiller.findMatches(["电机功率", "整备质量"], library: Self.library)
        let fuzzyItem = items.first { $0.confidence < 1.0 } ?? items[0]
        let fixes = SmartFiller.quickFixes(for: fuzzyItem, library: Self.library)
        XCTAssertLessThanOrEqual(fixes.count, 3)
        XCTAssertFalse(fixes.contains { $0.title == fuzzyItem.matchedParam?.name })
        // 满置信度无推荐
        let exact = items.first { $0.confidence == 1.0 }
        if let exact {
            XCTAssertTrue(SmartFiller.quickFixes(for: exact, library: Self.library).isEmpty)
        }
    }

    // MARK: 枚举字典

    func testEnumDictionaryBundledLoad() {
        let dict = EnumDictionary.loadBundled()
        XCTAssertGreaterThan(dict.count, 600, "内置字典应加载 686 行左右")
        // 360环视,/|无|标配
        let values = dict.enumValues(for: "360环视")
        XCTAssertEqual(values, ["/", "无", "标配"])
        // 标准化查找（全角括号/空格容错）
        XCTAssertTrue(dict.hasEnumValues(for: "360 环视"))
    }

    func testEnumMismatchDetection() {
        let dict = EnumDictionary.loadBundled()
        let requirement = "360环视"
        let items = SmartFiller.findMatches([requirement], library: Self.library)
        let item = items[0]
        if !item.effectiveValue.isEmpty {
            let mismatch = SmartFiller.isEnumMismatch(item, dictionary: dict)
            XCTAssertEqual(mismatch, !dict.enumValues(for: requirement).contains(item.effectiveValue))
        }
        // 手动改值后异常检测跟随
        let bad = SmartFiller.updateManualValue(item, "不存在的值")
        XCTAssertTrue(SmartFiller.isEnumMismatch(bad, dictionary: dict))
    }

    // MARK: 车上云导出 + 回读

    /// 导出 xlsx 必须能被（CoreXLSX）读回且内容一致——M2 验收"可被旧版读回"的同构验证
    func testVehicleCloudExportRoundTrip() throws {
        let items = SmartFiller.findMatches(Self.golden.requirementNames, library: Self.library)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vehicle_cloud_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: temp) }

        try XlsxWriter.writeVehicleCloudTemplate(items: items, productName: "测试车型DNC5037", to: temp)

        // 读回验证
        let sheets = try SheetGridLoader.load(url: temp)
        XCTAssertEqual(sheets.count, 1)
        XCTAssertEqual(sheets[0].name, "产品准入导入模版")
        let grid = sheets[0].grid
        let expected = SmartFiller.vehicleCloudRows(items)
        XCTAssertEqual(grid.count, expected.count)
        for (r, row) in expected.enumerated() {
            for (c, value) in row.enumerated() {
                // libxlsxwriter 把空字符串写为空白单元格（旧版 rust_xlsxwriter 同库同
                // 行为，SheetJS 读回 undefined）——回读 nil 视作 ""
                XCTAssertEqual(grid.cell(r, c)?.jsString ?? "", value, "r\(r)c\(c) 回读不一致")
            }
        }
    }

    /// 导出文件可被 CoreXLSX（独立解析栈）读回 —— 双栈交叉验证
    func testExportReadableByCoreXLSX() throws {
        let items = [MatchItem(id: "req-0", requirementName: "整备质量",
                               matchedParam: VehicleParameter(id: "1", group: "g", name: "整备质量",
                                                              value: .string("1780")),
                               confidence: 1.0)]
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("corexlsx_check_\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: temp) }
        try XlsxWriter.write(
            rows: [["参数项名称", "参数值"], ["整备质量", "1780"]],
            sheetName: "产品准入导入模版",
            colWidths: [30, 40],
            to: temp
        )
        // CoreXLSX 打开 + 解析 worksheet XML（与我们的 XMLParser 栈独立）
        let file = try XCTUnwrap(XLSXFile(filepath: temp.path))
        let workbook = try XCTUnwrap(file.parseWorkbooks().first)
        XCTAssertEqual(workbook.sheets.items.first?.name, "产品准入导入模版")
        let worksheet = try file.parseWorksheet(at: "xl/worksheets/sheet1.xml")
        XCTAssertEqual(worksheet.sheetData.rows.count, 2)
    }

    // MARK: 产品置信度

    func testProductConfidenceLevels() {
        // 黑名单直接低分
        let blacklisted = ProductConfidenceEvaluator.evaluate(productName: "必填", paramCount: 100)
        XCTAssertEqual(blacklisted.level, .low)
        // 真实车型名：字母+数字 + 电池特征 → 高分
        let real = ProductConfidenceEvaluator.evaluate(
            productName: "DNC5037XXYBEVP1 宁德时代 50kWh", paramCount: 326)
        XCTAssertEqual(real.level, .high)
        // 参数过少 + 纯中文短名 → 低分
        let weak = ProductConfidenceEvaluator.evaluate(productName: "备注", paramCount: 3)
        XCTAssertEqual(weak.level, .low)
        XCTAssertEqual(weak.reason, "参数数量过少(3)")
    }
}
