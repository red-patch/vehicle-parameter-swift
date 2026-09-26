import XCTest
@testable import VehicleKit

final class VehicleParameterTests: XCTestCase {
    // MARK: - value 双态编解码（旧版 string | number 桥接）

    func testStringValueRoundTrip() throws {
        let json = #"{"id":"p1","group":"动力","name":"电机峰值功率","value":"150kW"}"#
        let param = try JSONDecoder().decode(VehicleParameter.self, from: Data(json.utf8))
        XCTAssertEqual(param.value, .string("150kW"))
        XCTAssertEqual(param.displayValue, "150kW")
    }

    func testIntegerNumberRoundTripStaysInteger() throws {
        // 旧版 JSON.stringify 会把整数数字写为 123 而非 123.0，往返必须保持
        let json = #"{"id":"p1","group":"车身","name":"车门数","value":123}"#
        let param = try JSONDecoder().decode(VehicleParameter.self, from: Data(json.utf8))
        XCTAssertEqual(param.value, .number(123))

        let encoded = String(data: try JSONEncoder().encode(param), encoding: .utf8)!
        XCTAssertTrue(encoded.contains(#""value":123"#), "整数不得漂移为 123.0：\(encoded)")
    }

    func testFractionalNumberRoundTrip() throws {
        let json = #"{"id":"p1","group":"动力","name":"百公里能耗","value":12.5}"#
        let param = try JSONDecoder().decode(VehicleParameter.self, from: Data(json.utf8))
        XCTAssertEqual(param.value, .number(12.5))
        XCTAssertEqual(param.displayValue, "12.5")
    }

    func testNullValueDecodesAsEmptyString() throws {
        // 旧数据中 value 可能为 null，收容为空串而不是解码失败
        let json = #"{"id":"p1","group":"g","name":"n","value":null}"#
        let param = try JSONDecoder().decode(VehicleParameter.self, from: Data(json.utf8))
        XCTAssertEqual(param.value, .string(""))
    }

    // MARK: - 可选字段

    func testOptionalFieldsOmittedWhenNil() throws {
        let param = VehicleParameter(id: "p1", group: "g", name: "n", value: .string("v"))
        let encoded = String(data: try JSONEncoder().encode(param), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("rowCheck"))
        XCTAssertFalse(encoded.contains("instanceKey"))
        XCTAssertFalse(encoded.contains("updatedAt"))
    }

    func testFullFieldSetRoundTrip() throws {
        let param = VehicleParameter(
            id: "整备质量",
            group: "车身",
            name: "整备质量",
            value: .number(1780),
            rowCheck: "需核对",
            originSheet: "整车参数",
            productName: "V6E 33l类",
            instanceKey: "excel::V6E.xlsx::V6E 33l类",
            updatedAt: "2026-09-26T08:00:00.000Z"
        )
        let data = try JSONEncoder().encode(param)
        let decoded = try JSONDecoder().decode(VehicleParameter.self, from: data)
        XCTAssertEqual(decoded, param)
        XCTAssertEqual(decoded.displayName, "车身 / 整备质量")
    }

    func testDisplayValueForEdgeNumbers() {
        XCTAssertEqual(ParameterValue.number(0).displayText, "0")
        XCTAssertEqual(ParameterValue.number(-42).displayText, "-42")
        XCTAssertEqual(ParameterValue.number(999_999_999_999_999).displayText, "999999999999999")
        // 超出整数安全域走 Swift 浮点描述（JS 会给 "1000000000000000"，仅展示层差异，无契约影响）
        XCTAssertEqual(ParameterValue.number(1e15).displayText, "1000000000000000.0")
        XCTAssertEqual(ParameterValue.number(0.1).displayText, "0.1")
    }
}
