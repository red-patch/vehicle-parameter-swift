import XCTest
@testable import VehicleKit

/// M3：车型实例 key 语义与旧版对齐测试
final class VehicleInstanceTests: XCTestCase {
    func testBuildAndParseRoundTrip() {
        let key = VehicleInstance.buildKey(source: .excel, fileName: "demo.xlsx", productName: "DNC5037")
        XCTAssertEqual(key, "excel::demo.xlsx::DNC5037")
        let parsed = VehicleInstance.parse(key)
        XCTAssertEqual(parsed?.source, .excel)
        XCTAssertEqual(parsed?.fileName, "demo.xlsx")
        XCTAssertEqual(parsed?.productName, "DNC5037")
    }

    func testParseRejectsInvalid() {
        XCTAssertNil(VehicleInstance.parse("excel::only-two"))
        XCTAssertNil(VehicleInstance.parse("::a.xlsx::b"))
        XCTAssertNil(VehicleInstance.parse("web::a.xlsx::b"))  // 非法来源
        XCTAssertNil(VehicleInstance.parse("asset::a.xlsx::")) // 空产品名
        // 产品名可含分隔符（第一个分隔符界定 source，第二个界定 fileName）
        let tricky = VehicleInstance.parse("asset::a.json::P::X")
        XCTAssertEqual(tricky?.productName, "P::X")
    }

    func testOptionLabelDedupSameName() {
        XCTAssertEqual(
            VehicleInstance.optionLabel("asset::新石器_X3.json::新石器_X3"),
            "新石器_X3")
        XCTAssertEqual(
            VehicleInstance.optionLabel("excel::demo.xlsx::DNC5037"),
            "DNC5037 · demo.xlsx")
        XCTAssertEqual(VehicleInstance.optionLabel("garbage"), "garbage")
    }

    func testDisplayLabelsDedupNumbering() {
        // 同产品名两个实例：短标签带序号。排序规则（旧版）：先文件名（zh numeric），
        // 再来源（asset 在 excel 前）
        let keys = [
            VehicleInstance.buildKey(source: .excel, fileName: "b.xlsx", productName: "V6E"),
            VehicleInstance.buildKey(source: .asset, fileName: "V6E.json", productName: "V6E"),
        ]
        let labels = VehicleInstance.displayLabels(for: keys)
        XCTAssertEqual(labels[keys[0]]?.shortLabel, "V6E（1）")  // b.xlsx < V6E.json
        XCTAssertEqual(labels[keys[1]]?.shortLabel, "V6E（2）")
        // 同文件名时 asset 排在 excel 前
        let sameFile = [
            VehicleInstance.buildKey(source: .excel, fileName: "x.json", productName: "V6E"),
            VehicleInstance.buildKey(source: .asset, fileName: "x.json", productName: "V6E"),
        ]
        let labels2 = VehicleInstance.displayLabels(for: sameFile)
        XCTAssertEqual(labels2[sameFile[1]]?.shortLabel, "V6E（1）")  // asset 优先
        XCTAssertEqual(labels2[sameFile[0]]?.shortLabel, "V6E（2）")
        // 单实例直接用产品名
        let single = VehicleInstance.displayLabels(for: ["excel::a.xlsx::X"])
        XCTAssertEqual(single["excel::a.xlsx::X"]?.shortLabel, "X")
    }

    func testMatchesSelectionByProductName() {
        XCTAssertTrue(VehicleInstance.matchesSelection(
            "asset::a.json::V6E", instanceKey: "excel::b.xlsx::V6E"))
        XCTAssertFalse(VehicleInstance.matchesSelection(
            "asset::a.json::V6E", instanceKey: "excel::b.xlsx::V8E"))
    }

    func testMetaFromParamPrefersExistingKey() {
        let param = VehicleParameter(id: "1", group: "g", name: "n", value: .string("v"),
                                     productName: "P", instanceKey: "asset::old.json::Old")
        let meta = VehicleInstance.metaFromParam(source: .excel, fileFileName: "new.xlsx", param: param)
        XCTAssertEqual(meta.key, "asset::old.json::Old")
        // 无 instanceKey 时从文件名+产品名推导
        let bare = VehicleParameter(id: "2", group: "g", name: "n", value: .string("v"), productName: "P")
        let derived = VehicleInstance.metaFromParam(source: .asset, fileFileName: "lib.json", param: bare)
        XCTAssertEqual(derived.key, "asset::lib.json::P")
    }
}
