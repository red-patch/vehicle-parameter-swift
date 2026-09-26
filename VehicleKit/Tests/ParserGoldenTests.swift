import XCTest
@testable import VehicleKit

/// 真实/合成 xlsx 样本解析结果与旧版 golden 的逐项对齐测试
final class ParserGoldenTests: XCTestCase {
    private static let golden: [String: GoldenParseEntry] = {
        try! JSONDecoder().decode([String: GoldenParseEntry].self, from: Golden.loadJSON("parse_golden"))
    }()

    /// fixture 文件名（保持原始名——键值对/横向格式的产品名取自文件名）-> 旧仓库原始路径 key
    private static let fixtureMap: [(fixture: String, key: String)] = [
        ("02-地上铁需求参数反馈（02月03日版本）.xlsx", "02-地上铁需求参数反馈（02月03日版本）.xlsx"),
        ("02-地上铁需求参数反馈（9月25日版本）.xlsx", "02-地上铁需求参数反馈（9月25日版本）.xlsx"),
        ("demo.xlsx", "demo.xlsx"),
        ("demo_new.xlsx", "demo_new.xlsx"),
        ("demo1.xlsx", "demo1.xlsx"),
        ("need_param_simple.xlsx", "need_param_simple.xlsx"),
        ("old.xlsx", "V1.3/old.xlsx"),
        ("new.xlsx", "V1.3/new.xlsx"),
        ("DNC5037XXYBEVP1（旧）.xlsx", "V1.3/DNC5037XXYBEVP1（旧）.xlsx"),
        ("V8E客运版不支持.xlsx", "V8E客运版不支持.xlsx"),
        ("unit_vertical.xlsx", "synth:unit_vertical.xlsx"),
        ("unit_multirow.xlsx", "synth:unit_multirow.xlsx"),
        ("unit_keyvalue.xlsx", "synth:unit_keyvalue.xlsx"),
        ("unit_alias.xlsx", "synth:unit_alias.xlsx"),
    ]

    func testParseParityOnAllFixtures() throws {
        var checked = 0
        for (fixture, key) in Self.fixtureMap {
            guard let entry = Self.golden[key] else {
                XCTFail("golden 缺少 key：\(key)")
                continue
            }
            do {
                let sheet = try ExcelParser.parse(url: Golden.url(fixture))
                if !entry.ok {
                    XCTFail("\(fixture) 预期解析失败但 Swift 解析成功（\(sheet.data.count) 参数）")
                    continue
                }
                XCTAssertEqual(sheet.data.count, entry.count ?? -1, "\(fixture) 参数数量不一致")
                XCTAssertEqual(Set(sheet.data.compactMap(\.productName)), Set(entry.products ?? []),
                               "\(fixture) 产品集合不一致")
                XCTAssertEqual(Set(sheet.data.compactMap(\.originSheet)), Set(entry.sheets ?? []),
                               "\(fixture) Sheet 集合不一致")
                // 摘要一致性（验证 canonical 化口径，供后续非提交文件比对使用）
                if let expectedDigest = entry.sha256 {
                    XCTAssertEqual(Golden.digest(sheet.data), expectedDigest, "\(fixture) SHA256 摘要不一致")
                }
                // 全量清单逐项对比
                if let expectedParams = entry.parameters {
                    assertParametersMatch(sheet.data, expectedParams)
                }
                checked += 1
            } catch {
                if entry.ok {
                    XCTFail("\(fixture) 预期解析成功但 Swift 抛错：\(error)")
                } else {
                    // 预期失败：错误消息与诊断建议应在
                    let parseError = error as? ParseError
                    XCTAssertNotNil(parseError, "\(fixture) 应抛 ParseError，实际 \(error)")
                    XCTAssertFalse(parseError?.diagnostics.suggestion.isEmpty ?? true)
                }
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 14, "应有 14 个样本全部被校验")
    }

    /// 诊断信息语义保留（被跳过 sheet 的原因可读）
    func testDiagnosticsOnUnparseable() {
        XCTAssertThrowsError(try ExcelParser.parse(url: Golden.url("V8E客运版不支持.xlsx"))) { error in
            guard let parseError = error as? ParseError else {
                return XCTFail("应抛 ParseError")
            }
            XCTAssertEqual(parseError.message, "无法解析文件，未找到有效的参数数据")
            XCTAssertFalse(parseError.diagnostics.sheetsSkipped.isEmpty)
            XCTAssertFalse(parseError.diagnostics.suggestion.isEmpty)
        }
    }

    /// M1 性能验收口径：中大型真实文件解析 < 1s（demo1：7 个 sheet、1631 参数、12 产品）
    func testParsePerformanceUnderOneSecond() throws {
        let url = Golden.url("demo1.xlsx")
        // 预热（首次含 xml 解析器/动态库开销，以二次计时为准）
        _ = try ExcelParser.parse(url: url)
        let start = CFAbsoluteTimeGetCurrent()
        let sheet = try ExcelParser.parse(url: url)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        XCTAssertEqual(sheet.data.count, 1631)
        XCTAssertLessThan(elapsed, 1.0, "解析耗时 \(elapsed)s 超出 1s 预算")
    }

    // MARK: - 关键语义独立用例

    func testPercentConversion() throws {
        // 最大爬坡度 0.25 → "25%"（Excel 百分比存储还原）
        let sheet = try ExcelParser.parse(url: Golden.url("unit_vertical.xlsx"))
        let slope = sheet.data.first { $0.name == "最大爬坡度" && $0.productName == "DNC5037" }
        XCTAssertEqual(slope?.displayValue, "25%")
        let efficiency = sheet.data.first { $0.name == "充电效率" && $0.productName == "金旅ET850" }
        XCTAssertEqual(efficiency?.displayValue, "95%")
    }

    func testGroupFillDown() throws {
        // 分组列空值沿承上一个非空分组（Fill-Down）
        let sheet = try ExcelParser.parse(url: Golden.url("unit_vertical.xlsx"))
        let power = sheet.data.first { $0.name == "电机额定功率" && $0.productName == "DNC5037" }
        XCTAssertEqual(power?.group, "动力")
        let wheelbase = sheet.data.first { $0.name == "轴距(mm)" && $0.productName == "DNC5037" }
        XCTAssertEqual(wheelbase?.group, "动力")
    }

    func testMultiRowHeaderProductFromNextRow() throws {
        // 跨行表头：单"参数值"占位符 + 下一行产品名 DNC5037XXYBEVP1
        let sheet = try ExcelParser.parse(url: Golden.url("unit_multirow.xlsx"))
        XCTAssertEqual(sheet.data.count, 2)
        XCTAssertTrue(sheet.data.allSatisfy { $0.productName == "DNC5037XXYBEVP1" })
    }

    func testKeyValueFormatWithGroupHeaders() throws {
        let sheet = try ExcelParser.parse(url: Golden.url("unit_keyvalue.xlsx"))
        XCTAssertEqual(sheet.data.count, 6)
        let battery = sheet.data.first { $0.name == "电机额定功率" }
        XCTAssertEqual(battery?.group, "动力信息")
        XCTAssertEqual(battery?.displayValue, "100kW")
    }
}
