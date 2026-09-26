import Foundation

// MARK: - Fuse.js 7.1.0 精确移植
//
// 与旧版 matchingEngine.ts 的 Fuse 配置逐项对齐（keys: ['name'], includeScore,
// threshold, ignoreLocation, useExtendedSearch），打分/排序/边界语义必须与
// fuse.js@7.1.0 完全一致——这是 golden 四态计数契约的一部分，改动需双向同步。
//
// 移植要点：
// - JS String 按 UTF-16 code unit 索引，故 pattern/text 一律转 [UInt16] 处理
// - JS 位运算符按 int32 解释，这里用 UInt32 的 wrapping 运算复现相同位型
// - norm（字段长度范数）= 1/sqrt(非空格 token 数)，保留 3 位小数
// - 最终分 = pow(bitap 原始分, norm)

/// Fuse 搜索选项（与 fuse.js Config 对齐，只保留本项目用到的子集）
public struct FuseOptions: Sendable {
    public var location = 0
    public var threshold = 0.6
    public var distance = 100
    public var isCaseSensitive = false
    public var ignoreLocation = false
    public var useExtendedSearch = false
    public var minMatchCharLength = 1
    public var findAllMatches = false
    public var ignoreFieldNorm = false
    public var fieldNormWeight = 1.0

    public init() {}
}

// MARK: 位运算辅助（JS int32 语义中越界读为 undefined，参与位运算时按 0）

@inline(__always)
private func bitsAt(_ arr: [UInt32], _ i: Int) -> UInt32 {
    i >= 0 && i < arr.count ? arr[i] : 0
}

// MARK: - Bitap 核心

private let maxBits = 32

/// computeScore$1（fuse.js）
@inline(__always)
private func bitapScore(
    patternLen: Int,
    errors: Int,
    currentLocation: Int,
    expectedLocation: Int,
    distance: Int,
    ignoreLocation: Bool
) -> Double {
    let accuracy = Double(errors) / Double(patternLen)
    if ignoreLocation { return accuracy }
    let proximity = abs(expectedLocation - currentLocation)
    if distance == 0 { return proximity != 0 ? 1.0 : accuracy }
    return accuracy + Double(proximity) / Double(distance)
}

private struct BitapOutcome {
    var isMatch = false
    var score = 1.0
}

/// fuse.js search(text, pattern, patternAlphabet, options)
private func bitapSearch(
    text: [UInt16],
    pattern: [UInt16],
    alphabet: [UInt16: UInt32],
    location: Int,
    distance: Int,
    threshold: Double,
    findAllMatches: Bool,
    ignoreLocation: Bool
) -> BitapOutcome {
    let patternLen = pattern.count
    let textLen = text.count
    let expectedLocation = max(0, min(location, textLen))
    var currentThreshold = threshold
    var bestLocation = expectedLocation

    // 所有精确命中的快速扫描（用于收紧阈值）
    var searchFrom = bestLocation
    while let index = indexOf(pattern, in: text, from: searchFrom) {
        let score = bitapScore(
            patternLen: patternLen, errors: 0, currentLocation: index,
            expectedLocation: expectedLocation, distance: distance, ignoreLocation: ignoreLocation
        )
        currentThreshold = min(score, currentThreshold)
        bestLocation = index + patternLen
        searchFrom = bestLocation
    }

    bestLocation = -1
    var lastBitArr: [UInt32] = []
    var finalScore = 1.0
    var binMax = patternLen + textLen
    let mask: UInt32 = patternLen > 0 ? (UInt32(1) << UInt32(patternLen - 1)) : 0

    for i in 0..<patternLen {
        // 二分确定该错误级别下允许的偏离半径
        var binMin = 0
        var binMid = binMax
        while binMin < binMid {
            let score = bitapScore(
                patternLen: patternLen, errors: i,
                currentLocation: expectedLocation + binMid,
                expectedLocation: expectedLocation, distance: distance, ignoreLocation: ignoreLocation
            )
            if score <= currentThreshold { binMin = binMid } else { binMax = binMid }
            binMid = (binMax - binMin) / 2 + binMin
        }
        binMax = binMid
        var start = max(1, expectedLocation - binMid + 1)
        let finish = findAllMatches ? textLen : min(expectedLocation + binMid, textLen) + patternLen

        var bitArr = [UInt32](repeating: 0, count: finish + 2)
        bitArr[finish + 1] = (UInt32(1) << UInt32(i)) &- 1
        var j = finish
        while j >= start {
            let currentLocation = j - 1
            let charMatch = currentLocation >= 0 && currentLocation < textLen
                ? alphabet[text[currentLocation]] ?? 0 : 0

            // 精确传递 + 模糊传递（JS: (bitArr[j+1]<<1|1)&charMatch | ((last|last)<<1|1|last)）
            let shifted = (bitsAt(bitArr, j + 1) << 1) | 1
            bitArr[j] = shifted & charMatch
            if i > 0 {
                let fuzzy = ((bitsAt(lastBitArr, j + 1) | bitsAt(lastBitArr, j)) << 1) | 1 | bitsAt(lastBitArr, j + 1)
                bitArr[j] = bitArr[j] | fuzzy
            }
            if bitArr[j] & mask != 0 {
                let score = bitapScore(
                    patternLen: patternLen, errors: i, currentLocation: currentLocation,
                    expectedLocation: expectedLocation, distance: distance, ignoreLocation: ignoreLocation
                )
                finalScore = score
                if score <= currentThreshold {
                    currentThreshold = score
                    bestLocation = currentLocation
                    if bestLocation <= expectedLocation { break }
                    // 抬升下界：不超过当前与 expectedLocation 的偏离
                    start = max(1, 2 * expectedLocation - bestLocation)
                }
            }
            j -= 1
        }

        // 下一错误级别已无希望
        let nextLevel = bitapScore(
            patternLen: patternLen, errors: i + 1, currentLocation: expectedLocation,
            expectedLocation: expectedLocation, distance: distance, ignoreLocation: ignoreLocation
        )
        if nextLevel > currentThreshold { break }
        lastBitArr = bitArr
    }

    return BitapOutcome(isMatch: bestLocation >= 0, score: max(0.001, finalScore))
}

/// UTF-16 indexOf（等价 JS String.prototype.indexOf 的 fromIndex 语义）
private func indexOf(_ needle: [UInt16], in haystack: [UInt16], from: Int) -> Int? {
    guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
    let effectiveFrom = max(0, from)
    guard effectiveFrom <= haystack.count - needle.count else { return nil }
    outer: for i in effectiveFrom...(haystack.count - needle.count) {
        for k in 0..<needle.count where haystack[i + k] != needle[k] { continue outer }
        return i
    }
    return nil
}

/// createPatternAlphabet
private func patternAlphabet(of pattern: [UInt16]) -> [UInt16: UInt32] {
    var mask: [UInt16: UInt32] = [:]
    let len = pattern.count
    for (i, unit) in pattern.enumerated() {
        mask[unit] = (mask[unit] ?? 0) | (UInt32(1) << UInt32(len - i - 1))
    }
    return mask
}

// MARK: - 扩展搜索 token（useExtendedSearch）

/// token 匹配器种类（注册顺序影响归属：普通 token 最终落到 fuzzy）
private enum TokenKind {
    case exact            // =foo / ="foo"
    case include          // 'foo
    case prefixExact      // ^foo / ^"foo"
    case inversePrefix    // !^foo
    case inverseSuffix    // !foo$
    case suffixExact      // foo$ / "foo"$
    case inverseExact     // !foo / !"foo"
    case fuzzy            // foo / "foo"（bitap）
}

private struct TokenSearcher {
    let kind: TokenKind
    let pattern: String
    let units: [UInt16]
    let options: FuseOptions

    init(kind: TokenKind, pattern: String, options: FuseOptions) {
        self.kind = kind
        self.pattern = pattern
        // BitapSearch 构造时已做 lowercase
        let lowered = options.isCaseSensitive ? pattern : pattern.lowercased()
        self.units = Array(lowered.utf16)
        self.options = options
    }

    func search(in textUnits: [UInt16], textLower: String) -> BitapOutcome {
        switch kind {
        case .exact:
            // text === pattern
            let matched = textLower == pattern
            return BitapOutcome(isMatch: matched, score: matched ? 0 : 1)
        case .inverseExact:
            return BitapOutcome(isMatch: indexOf(units, in: textUnits, from: 0) == nil, score: 0)
        case .prefixExact:
            return BitapOutcome(isMatch: hasPrefix(textUnits, units), score: 0)
        case .inversePrefix:
            return BitapOutcome(isMatch: !hasPrefix(textUnits, units), score: 0)
        case .suffixExact:
            return BitapOutcome(isMatch: hasSuffix(textUnits, units), score: 0)
        case .inverseSuffix:
            return BitapOutcome(isMatch: !hasSuffix(textUnits, units), score: 0)
        case .include:
            return BitapOutcome(isMatch: indexOf(units, in: textUnits, from: 0) != nil, score: 0)
        case .fuzzy:
            return bitapChunkedSearch(text: textUnits)
        }
    }

    /// 未命中返回 score 1；命中按 bitap 块平均
    private func bitapChunkedSearch(text: [UInt16]) -> BitapOutcome {
        if units.isEmpty { return BitapOutcome(isMatch: false, score: 1) }
        if pattern.isEmpty { return BitapOutcome(isMatch: false, score: 1) }
        // pattern === text 快速路径（BitapSearch.searchIn 首查）
        if units.count == text.count && units == text {
            return BitapOutcome(isMatch: true, score: 0)
        }
        var totalScore = 0.0
        var hasMatches = false
        // 块化（pattern > 32 时按 MAX_BITS 分块；本项目名称长度不会触发，仍按源码实现）
        var chunks: [(pattern: [UInt16], startIndex: Int)] = []
        if units.count > maxBits {
            let remainder = units.count % maxBits
            let end = units.count - remainder
            var i = 0
            while i < end {
                chunks.append((Array(units[i..<min(i + maxBits, units.count)]), i))
                i += maxBits
            }
            if remainder > 0 {
                let startIndex = units.count - maxBits
                chunks.append((Array(units[startIndex...]), startIndex))
            }
        } else {
            chunks.append((units, 0))
        }
        for chunk in chunks {
            let outcome = bitapSearch(
                text: text, pattern: chunk.pattern,
                alphabet: patternAlphabet(of: chunk.pattern),
                location: options.location + chunk.startIndex,
                distance: options.distance,
                threshold: options.threshold,
                findAllMatches: options.findAllMatches,
                ignoreLocation: options.ignoreLocation
            )
            if outcome.isMatch { hasMatches = true }
            totalScore += outcome.score
        }
        return BitapOutcome(
            isMatch: hasMatches,
            score: hasMatches ? totalScore / Double(chunks.count) : 1
        )
    }

    private func hasPrefix(_ text: [UInt16], _ prefix: [UInt16]) -> Bool {
        text.count >= prefix.count && Array(text[0..<prefix.count]) == prefix
    }

    private func hasSuffix(_ text: [UInt16], _ suffix: [UInt16]) -> Bool {
        text.count >= suffix.count && Array(text[(text.count - suffix.count)...]) == suffix
    }
}

/// parseQuery：按 `|` 分 OR 组，组内按空格分 token 并归属匹配器
private func parseQuery(_ pattern: String, options: FuseOptions) -> [[TokenSearcher]] {
    pattern.split(separator: "|", omittingEmptySubsequences: false).map { orGroup in
        let trimmed = orGroup.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        // JS: trim().split(/ +/)，空串 split 结果为 ['']，被 filter 掉
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        var results: [TokenSearcher] = []
        for token in tokens {
            let queryItem = String(token)
            // 多词匹配（带引号）按注册顺序尝试
            if let searcher = multiMatch(queryItem, options: options) {
                results.append(searcher)
                continue
            }
            // 单词匹配
            if let searcher = singleMatch(queryItem, options: options) {
                results.append(searcher)
            }
        }
        return results
    }
}

private func multiMatch(_ token: String, options: FuseOptions) -> TokenSearcher? {
    // 顺序即 fuse.js searchers 数组：Exact, Include, Prefix, InversePrefix,
    // InverseSuffix, Suffix, InverseExact, Fuzzy
    if let m = matchRegex(token, pattern: "^=\"(.*)\"$") {
        return TokenSearcher(kind: .exact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^'(.*)$") {
        return TokenSearcher(kind: .include, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^\\^\"(.*)\"$") {
        return TokenSearcher(kind: .prefixExact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^!\\^\"(.*)\"$") {
        return TokenSearcher(kind: .inversePrefix, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^!\"(.*)\"\\$$") {
        return TokenSearcher(kind: .inverseSuffix, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^\"(.*)\"\\$$") {
        return TokenSearcher(kind: .suffixExact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^!\"(.*)\"$") {
        return TokenSearcher(kind: .inverseExact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^\"(.*)\"$") {
        return TokenSearcher(kind: .fuzzy, pattern: m, options: options)
    }
    return nil
}

private func singleMatch(_ token: String, options: FuseOptions) -> TokenSearcher? {
    if let m = matchRegex(token, pattern: "^=(.*)$") {
        return TokenSearcher(kind: .exact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^'(.*)$") {
        return TokenSearcher(kind: .include, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^\\^(.*)$") {
        return TokenSearcher(kind: .prefixExact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^!\\^(.*)$") {
        return TokenSearcher(kind: .inversePrefix, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^!(.*)\\$$") {
        return TokenSearcher(kind: .inverseSuffix, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^(.*)\\$$") {
        return TokenSearcher(kind: .suffixExact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^!(.*)$") {
        return TokenSearcher(kind: .inverseExact, pattern: m, options: options)
    }
    if let m = matchRegex(token, pattern: "^(.*)$") {
        return TokenSearcher(kind: .fuzzy, pattern: m, options: options)
    }
    return nil
}

private func matchRegex(_ input: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(input.startIndex..<input.endIndex, in: input)
    guard let m = regex.firstMatch(in: input, range: range),
          m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: input) else { return nil }
    return String(input[r])
}

// MARK: - 索引与主流程

/// norm()：字段长度范数，token 数按空格切分（含 \t 等非空格字符的连续段算一个 token）
private func fieldNorm(_ value: String, weight: Double) -> Double {
    let numTokens = value.split(separator: " ", omittingEmptySubsequences: true).count
    let m = 1000.0
    let norm = 1 / Foundation.pow(Double(numTokens), 0.5 * weight)
    return (norm * m).rounded() / m
}

public struct FuseResult: Sendable {
    public let index: Int
    public let score: Double
}

/// Fuse 实例（对一组文本构建索引后可反复查询）
public final class FuseEngine: @unchecked Sendable {
    private struct Record {
        let units: [UInt16]
        let lower: String
        let norm: Double
        let idx: Int
    }

    private let records: [Record]
    private let options: FuseOptions

    /// - Parameters:
    ///   - texts: 候选文本（对应旧版 candidates 的 name 列表，顺序即文档顺序）
    ///   - options: 阈值等配置（旧版固定 keys:['name'], ignoreLocation:true,
    ///     useExtendedSearch:true，此处由调用方传入完整 options）
    public init(texts: [String], options: FuseOptions) {
        self.options = options
        var records: [Record] = []
        for (i, text) in texts.enumerated() {
            // 空白值不入索引（fuse.js isBlank 过滤）
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let lower = options.isCaseSensitive ? text : text.lowercased()
            records.append(Record(
                units: Array(lower.utf16),
                lower: lower,
                norm: fieldNorm(text, weight: options.fieldNormWeight),
                idx: i
            ))
        }
        self.records = records
    }

    /// search(query)：返回 (index, score) 列表，按 score 升序、index 升序（shouldSort + sortFn）
    public func search(_ query: String) -> [FuseResult] {
        let lowered = options.isCaseSensitive ? query : query.lowercased()
        let searchers: [[TokenSearcher]]
        if options.useExtendedSearch {
            searchers = parseQuery(lowered, options: options)
        } else {
            searchers = [[TokenSearcher(kind: .fuzzy, pattern: lowered, options: options)]]
        }

        var results: [FuseResult] = []
        for record in records {
            var rawScore: Double?
            orLoop: for group in searchers where !group.isEmpty {
                var totalScore = 0.0
                var numMatches = 0
                for searcher in group {
                    let outcome = searcher.search(in: record.units, textLower: record.lower)
                    if outcome.isMatch {
                        numMatches += 1
                        totalScore += outcome.score
                    } else {
                        totalScore = 0
                        numMatches = 0
                        continue orLoop
                    }
                }
                if numMatches > 0 {
                    rawScore = totalScore / Double(numMatches)
                    break orLoop
                }
            }
            if let raw = rawScore {
                // computeScore: pow(raw, norm)（无 key weight 路径）
                let score = options.ignoreFieldNorm
                    ? raw
                    : pow(raw == 0 ? 0 : raw, record.norm)
                results.append(FuseResult(index: record.idx, score: score))
            }
        }
        results.sort { a, b in
            a.score == b.score ? a.index < b.index : a.score < b.score
        }
        return results
    }
}
