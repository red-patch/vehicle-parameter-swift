import SwiftUI
import VehicleKit

@main
struct VehicleParameterApp: App {
    @State private var router = AppRouter()
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        WindowGroup {
            MainShell()
                .environment(router)
        }
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(router: router, updater: updater)
        }
    }
}

/// 菜单栏：全快捷键（M5）
struct AppCommands: Commands {
    let router: AppRouter
    let updater: UpdaterController

    var body: some Commands {
        // 功能切换菜单
        SidebarCommands()
        CommandMenu("功能") {
            ForEach(Feature.allCases) { feature in
                Button(feature.rawValue) {
                    router.switchTo(feature)
                }
                .keyboardShortcut(Self.shortcut(for: feature))
            }
        }
        // 文件菜单增强
        CommandGroup(replacing: .newItem) {
            Button("打开参数 Excel…") {
                NotificationCenter.default.post(name: .globalOpenFile, object: nil)
            }
            .keyboardShortcut("o")

            Button("保存到资产库") {
                NotificationCenter.default.post(name: .globalSave, object: nil)
            }
            .keyboardShortcut("s")

            Button("导出 PDF 报告") {
                NotificationCenter.default.post(name: .globalSave, object: "pdf")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        // 查找（并入功能菜单）
        CommandMenu("查找") {
            Button("查找参数") {
                NotificationCenter.default.post(name: .globalFocusSearch, object: nil)
            }
            .keyboardShortcut("f")
        }
        // 检查更新（Sparkle）
        CommandGroup(after: .appInfo) {
            Button("检查更新…") {
                updater.checkForUpdates()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(!updater.canCheckForUpdates)
        }
    }

    private static func shortcut(for feature: Feature) -> KeyEquivalent {
        switch feature {
        case .compare: "1"
        case .smartFill: "2"
        case .assetLibrary: "3"
        case .purify: "4"
        case .dedup: "5"
        case .announcement: "6"
        }
    }
}
