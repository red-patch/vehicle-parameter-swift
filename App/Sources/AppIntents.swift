import AppIntents
import Foundation

// MARK: - Shortcuts 自动化（App Intents）

/// 功能页枚举（App Enum 供 Shortcuts 参数选择）
enum FeatureAppEntity: String, AppEnum {
    case compare, smartFill, assetLibrary, purify, dedup, announcement

    static let typeDisplayRepresentation: TypeDisplayRepresentation =
        .init(name: "功能页")

    static let caseDisplayRepresentations: [FeatureAppEntity: DisplayRepresentation] = [
        .compare: .init(title: "版本对比"),
        .smartFill: .init(title: "智能填报"),
        .assetLibrary: .init(title: "资产库"),
        .purify: .init(title: "数据净化"),
        .dedup: .init(title: "属性去重"),
        .announcement: .init(title: "公告查询"),
    ]

    var feature: Feature {
        switch self {
        case .compare: .compare
        case .smartFill: .smartFill
        case .assetLibrary: .assetLibrary
        case .purify: .purify
        case .dedup: .dedup
        case .announcement: .announcement
        }
    }
}

/// 切换功能页（可在 Shortcuts 中串联）
struct SwitchFeatureIntent: AppIntent {
    static let title: LocalizedStringResource = "切换功能页"
    static let description = IntentDescription("在车辆参数工具中切换到指定功能页")

    @Parameter(title: "功能页")
    var target: FeatureAppEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .switchFeature, object: target.feature.rawValue)
        return .result()
    }
}

struct VehicleParameterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SwitchFeatureIntent(),
            phrases: [
                "在\(.applicationName)切换功能页",
                "打开\(.applicationName)的\(\.$target)",
            ],
            shortTitle: "切换功能页",
            systemImageName: "square.grid.2x2"
        )
    }
}
