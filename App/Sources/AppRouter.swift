import AppKit
import Observation
import Sparkle

// MARK: - 功能路由与全局动作（菜单快捷键 / Shortcuts 共用）

enum Feature: String, CaseIterable, Identifiable {
    case compare = "版本对比"
    case smartFill = "智能填报"
    case assetLibrary = "资产库"
    case purify = "数据净化"
    case dedup = "属性去重"
    case announcement = "公告查询"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .compare: "arrow.left.arrow.right.square"
        case .smartFill: "text.badge.checkmark"
        case .assetLibrary: "archivebox"
        case .purify: "checklist"
        case .dedup: "tablecells.badge.ellipsis"
        case .announcement: "globe.asia.australia"
        }
    }
}

extension Notification.Name {
    /// 切换功能页（object: Feature.rawValue）
    static let switchFeature = Notification.Name("switchFeature")
    /// 全局打开文件动作（Cmd+O）
    static let globalOpenFile = Notification.Name("globalOpenFile")
    /// 全局保存动作（Cmd+S）
    static let globalSave = Notification.Name("globalSave")
    /// 全局查找聚焦（Cmd+F）
    static let globalFocusSearch = Notification.Name("globalFocusSearch")
}

@MainActor
@Observable
final class AppRouter {
    /// 当前功能页（持久化——窗口状态记忆）
    var selectedFeature: Feature {
        get {
            Feature(rawValue: UserDefaults.standard.string(forKey: "selectedFeature") ?? "") ?? .compare
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedFeature")
        }
    }

    /// Quick Look 展示的文件
    var quickLookURL: URL?

    func switchTo(_ feature: Feature) {
        selectedFeature = feature
    }

    func openQuickLook(url: URL) {
        quickLookURL = url
    }
}

// MARK: - Sparkle 更新器

@MainActor
final class UpdaterController: ObservableObject {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var updater: SPUUpdater { controller.updater }

    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
