import Quartz
import SwiftUI
import VehicleKit

/// 主窗口壳 —— M5：侧栏导航（原生 macOS 范式，仅渲染当前页省内存）
/// + 菜单路由 + Quick Look + 状态记忆
struct MainShell: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: Binding(
                get: { router.selectedFeature },
                set: { router.switchTo($0) }
            )) { feature in
                Label(feature.rawValue, systemImage: feature.systemImage)
                    .tag(feature)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            // 仅渲染当前功能页（TabView 会实例化全部页签）
            featureView(router.selectedFeature)
                .frame(minWidth: 780, minHeight: 640)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .onReceive(NotificationCenter.default.publisher(for: .switchFeature)) { note in
            if let raw = note.object as? String, let feature = Feature(rawValue: raw) {
                router.switchTo(feature)
            }
        }
        .overlay {
            if let url = router.quickLookURL {
                QuickLookOverlay(url: url) {
                    router.quickLookURL = nil
                }
            }
        }
    }

    @ViewBuilder
    private func featureView(_ feature: Feature) -> some View {
        switch feature {
        case .compare: WorkbenchView()
        case .smartFill: SmartFillView()
        case .assetLibrary: AssetLibraryView()
        case .purify: DataPurifyView()
        case .dedup: AttributeDedupView()
        case .announcement: AnnouncementQueryView()
        }
    }
}

// MARK: - Quick Look 浮层（Quartz QLPreviewView）

struct QuickLookOverlay: NSViewRepresentable {
    let url: URL
    let close: () -> Void

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.previewItem = QuickLookItem(url: url)
        preview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.subviews.first as? QLPreviewView)?.previewItem = QuickLookItem(url: url)
    }
}

private final class QuickLookItem: NSObject, QLPreviewItem {
    let url: URL
    init(url: URL) { self.url = url }
    var previewItemURL: URL? { url }
}

#Preview {
    MainShell()
        .environment(AppRouter())
}
