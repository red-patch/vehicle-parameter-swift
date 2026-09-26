import Foundation
import Fuse

/// 模糊匹配引擎参数 —— 与旧版 `matchingEngine.ts` 的 Fuse 配置对齐。
/// 四级匹配语义（exact 0 / normalized 0.1 / alias 0.1-0.2 / fuzzy ≤0.3）是 golden 测试契约，
/// 阈值改动必须与旧版同步或说明理由。
public enum FuzzySearch {
    /// 旧版 Fuse.js 默认参数 + threshold 0.3
    public static let threshold = 0.3

    public static func makeEngine() -> Fuse {
        Fuse(threshold: threshold)
    }
}
