import XCTest
@testable import VehicleKit

final class AssetDocumentTests: XCTestCase {
    /// 与旧版 assetManager.ts 实际产出同构的样本（含中文字段与可选字段缺省）
    private static let legacySample = """
    {
      "version": "1.0",
      "productName": "V6E 33l类",
      "createdAt": "2025-03-01T09:30:00.000Z",
      "updatedAt": "2025-06-15T14:20:11.123Z",
      "parameters": [
        {
          "id": "整备质量",
          "group": "车身",
          "name": "整备质量",
          "value": 1780,
          "productName": "V6E 33l类"
        },
        {
          "id": "续航里程",
          "group": "动力",
          "name": "CLTC续航里程",
          "value": "560km",
          "originSheet": "整车参数",
          "instanceKey": "asset::V6E.json::V6E 33l类"
        }
      ]
    }
    """

    func testDecodeLegacyFormat() throws {
        let doc = try AssetDocument.decode(from: Data(Self.legacySample.utf8))
        XCTAssertEqual(doc.version, "1.0")
        XCTAssertEqual(doc.productName, "V6E 33l类")
        XCTAssertEqual(doc.parameters.count, 2)
        XCTAssertEqual(doc.parameters[0].value, .number(1780))
        XCTAssertEqual(doc.parameters[1].value, .string("560km"))
        XCTAssertNil(doc.parameters[0].rowCheck)
    }

    func testRoundTripPreservesSemantics() throws {
        let original = try AssetDocument.decode(from: Data(Self.legacySample.utf8))
        let decodedAgain = try AssetDocument.decode(from: try original.encoded())
        XCTAssertEqual(original, decodedAgain)
    }

    func testEncodedIntegerValueHasNoDecimalDrift() throws {
        let doc = try AssetDocument.decode(from: Data(Self.legacySample.utf8))
        let text = String(data: try doc.encoded(), encoding: .utf8)!
        // Xcode 16 的 JSONEncoder 会在冒号前后加空格，按空白无关方式断言数字形态
        let normalized = text.components(separatedBy: .whitespacesAndNewlines).joined()
        XCTAssertTrue(normalized.contains(#""value":1780,"#), "整数漂移为 1780.0 将破坏旧版读回：\(text)")
    }

    func testEncodedFormatIsIndentedLikeLegacyWriter() throws {
        let doc = try AssetDocument.decode(from: Data(Self.legacySample.utf8))
        let text = String(data: try doc.encoded(), encoding: .utf8)!
        XCTAssertTrue(text.contains("\n  \"productName\""), "应保持 2 空格缩进：\(text.prefix(80))…")
    }

    func testNewDocumentUsesCurrentFormatVersion() {
        let doc = AssetDocument(
            productName: "测试车型",
            createdAt: AssetDocument.nowTimestamp(),
            updatedAt: AssetDocument.nowTimestamp(),
            parameters: [
                VehicleParameter(id: "轴距", group: "车身", name: "轴距", value: .number(2900))
            ]
        )
        XCTAssertEqual(doc.version, AssetDocument.formatVersion)
        // 毫秒精度 ISO8601，与旧版 new Date().toISOString() 形态一致
        XCTAssertTrue(doc.updatedAt.hasSuffix("Z"))
        XCTAssertTrue(doc.updatedAt.contains("."))
    }
}
