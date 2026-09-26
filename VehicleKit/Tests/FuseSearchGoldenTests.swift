import XCTest
@testable import VehicleKit

/// FuseSearch（fuse.js 7.1.0 移植）与 MatchingEngine 的旧版分数级对齐测试
final class FuseSearchGoldenTests: XCTestCase {
    private static let golden: GoldenFuse = {
        try! JSONDecoder().decode(GoldenFuse.self, from: Golden.loadJSON("fuse_golden"))
    }()

    func testNormalizeNameParity() {
        for (input, expected) in Self.golden.norm {
            XCTAssertEqual(normalizeName(input), expected, "normalizeName(\(input)) 与旧版不一致")
        }
    }

    /// Fuse 引擎结果（索引列表 + 分数）与 fuse.js 逐项一致
    func testFuseEngineScoreParity() throws {
        let candidates = Self.golden.candidates
        for (key, expected) in Self.golden.fuse {
            let parts = key.split(separator: "|", maxSplits: 1)
            let threshold = Double(parts[0])!
            let query = String(parts[1])

            var options = FuseOptions()
            options.threshold = threshold
            options.ignoreLocation = true
            options.useExtendedSearch = true
            let engine = FuseEngine(texts: candidates, options: options)
            let results = engine.search(query)

            guard results.count == expected.count else {
                XCTFail("threshold=\(threshold) query=\(query)：命中数不一致 Swift=\(results.map(\.index)) golden=\(expected.map { Int($0[0]) })")
                continue
            }
            for (i, (actual, exp)) in zip(results, expected).enumerated() {
                XCTAssertEqual(actual.index, Int(exp[0]), "threshold=\(threshold) query=\(query) 第 \(i) 项索引不一致")
                assertClose(actual.score, exp[1], "threshold=\(threshold) query=\(query) 第 \(i) 项分数不一致")
            }
        }
    }

    /// findBestMatch 四级语义与旧版一致
    func testFindBestMatchParity() {
        let candidates = Self.golden.candidates.enumerated().map { i, name in
            VehicleParameter(id: "t\(i)", group: "g", name: name, value: .string("v\(i)"))
        }
        let index = CandidateIndex(candidates, threshold: 0.3)
        for (query, expected) in Self.golden.match {
            let result = findBestMatch(query, in: index, threshold: 0.3)
            XCTAssertEqual(result.matchType.rawValue, expected.type, "query=\(query) 匹配级别不一致")
            XCTAssertEqual(result.matchedParam?.name, expected.name, "query=\(query) 匹配目标不一致")
            assertClose(result.score, expected.score, "query=\(query) 分数不一致")
        }
    }

    // MARK: - 行为单元用例（移植关键点的独立确认）

    func testExactPathBeatsFuzzy() {
        let candidates = [VehicleParameter(id: "1", group: "g", name: "整备质量", value: .string("1780")),
                          VehicleParameter(id: "2", group: "g", name: "整备质量xx", value: .string("1"))]
        let result = findBestMatch("整备质量", candidates: candidates)
        XCTAssertEqual(result.matchType, .exact)
        XCTAssertEqual(result.matchedParam?.id, "1")
        XCTAssertEqual(result.score, 0)
    }

    func testAliasStandardWinsOverAlias() {
        // 查询别名 "车长" → 命中标准词 "外形尺寸长"（0.1），而非别的别名
        let candidates = [VehicleParameter(id: "1", group: "g", name: "外形尺寸长", value: .string("5990")),
                          VehicleParameter(id: "2", group: "g", name: "整车长", value: .string("6000"))]
        let result = findBestMatch("车长", candidates: candidates)
        XCTAssertEqual(result.matchType, .alias)
        XCTAssertEqual(result.matchedParam?.id, "1")
        XCTAssertEqual(result.score, 0.1)
    }

    func testNoMatchScore() {
        let candidates = [VehicleParameter(id: "1", group: "g", name: "轮胎规格", value: .string("195"))]
        let result = findBestMatch("foobar", candidates: candidates)
        XCTAssertNil(result.matchedParam)
        XCTAssertEqual(result.matchType, .none)
        XCTAssertEqual(result.score, 1)
    }

    func testFuseExactEqualityScoreZero() {
        // pattern === text 走快速路径，分数为 0（不经过 bitap 的 0.001 下限）
        var options = FuseOptions()
        options.threshold = 0.6
        options.ignoreLocation = true
        options.useExtendedSearch = true
        let engine = FuseEngine(texts: ["整备质量"], options: options)
        let results = engine.search("整备质量")
        XCTAssertEqual(results.first?.score ?? 1, 0.0, accuracy: 1e-12)
    }

    func testFuseBitapScoreFloor() {
        // 非 exact-equality 的零错误 bitap 命中，分数取 0.001 下限（fuse.js 语义）
        var options = FuseOptions()
        options.threshold = 0.6
        options.ignoreLocation = true
        options.useExtendedSearch = true
        let engine = FuseEngine(texts: ["整备质量(kg)"], options: options)
        let results = engine.search("整备质量")
        XCTAssertEqual(results.first?.score ?? 1, 0.001, accuracy: 1e-12)
    }
}
