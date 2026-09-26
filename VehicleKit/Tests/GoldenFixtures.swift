import CryptoKit
import Foundation
import XCTest
@testable import VehicleKit

// MARK: - Golden 基准装载与断言工具

enum Golden {
    static let bundle = Bundle.module

    static func url(_ fixture: String) -> URL {
        guard let url = bundle.url(forResource: (fixture as NSString).deletingPathExtension,
                                   withExtension: "xlsx",
                                   subdirectory: "Golden/Fixtures") else {
            fatalError("fixture 缺失：\(fixture)")
        }
        return url
    }

    static func loadJSON(_ name: String) -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Golden") else {
            fatalError("golden JSON 缺失：\(name)")
        }
        return try! Data(contentsOf: url)
    }

    /// 与导出脚本一致的规范化摘要：字段 \u{1F} 连接、参数 \u{1E} 连接、UTF-8 SHA256
    static func digest(_ params: [VehicleParameter]) -> String {
        let canonical = params.map { p in
            [p.id, p.group, p.name, p.displayValue, p.originSheet ?? "", p.productName ?? ""]
                .joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")
        let hash = SHA256.hash(data: Data(canonical.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Golden JSON 模型

struct GoldenParam: Codable, Equatable {
    let id: String
    let group: String
    let name: String
    let value: String
    let originSheet: String?
    let productName: String?
}

struct GoldenParseEntry: Codable {
    let ok: Bool
    var count: Int?
    var products: [String]?
    var sheets: [String]?
    var rawHeaders: [String]?
    var sha256: String?
    var parameters: [GoldenParam]?
    var error: String?
}

struct GoldenCompareEntry: Codable {
    struct Counts: Codable, Equatable {
        let added, removed, modified, unchanged: Int
    }
    struct ModifiedPair: Codable, Equatable {
        let id: String
        let old: GoldenParam
        let new: GoldenParam
    }
    let baseFile: String
    let targetFile: String
    let mode: String
    let counts: Counts
    let added: [GoldenParam]
    let removed: [GoldenParam]
    let modified: [ModifiedPair]
    let unchanged: [GoldenParam]
}

struct GoldenFuse: Codable {
    struct MatchOutcome: Codable, Equatable {
        let type: String
        let score: Double
        let name: String?
    }
    let candidates: [String]
    /// key "threshold|query" -> [[index, score], ...]
    let fuse: [String: [[Double]]]
    let match: [String: MatchOutcome]
    let norm: [String: String]
}

// MARK: - 断言助手

/// 逐字段对比解析结果与 golden 参数清单，首个差异给出可定位的失败信息
func assertParametersMatch(
    _ actual: [VehicleParameter], _ expected: [GoldenParam],
    file: StaticString = #filePath, line: UInt = #line
) {
    if actual.count != expected.count {
        XCTFail("参数数量不一致：Swift=\(actual.count) golden=\(expected.count)", file: file, line: line)
        return
    }
    for (i, (a, e)) in zip(actual, expected).enumerated() {
        if a.id != e.id || a.group != e.group || a.name != e.name || a.displayValue != e.value
            || a.originSheet != e.originSheet || a.productName != e.productName {
            XCTFail(
                """
                第 \(i) 个参数不一致：
                  Swift : id=\(a.id) group=\(a.group) name=\(a.name) value=\(a.displayValue) sheet=\(a.originSheet ?? "nil") product=\(a.productName ?? "nil")
                  golden: id=\(e.id) group=\(e.group) name=\(e.name) value=\(e.value) sheet=\(e.originSheet ?? "nil") product=\(e.productName ?? "nil")
                """,
                file: file, line: line)
            return
        }
    }
}

func assertClose(_ a: Double, _ b: Double, _ message: String = "", accuracy: Double = 1e-9,
                 file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a, b, accuracy: accuracy, message.isEmpty ? "" : message, file: file, line: line)
}
