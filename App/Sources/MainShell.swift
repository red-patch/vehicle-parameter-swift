import SwiftUI
import VehicleKit

/// 主窗口壳 —— M3：版本对比 / 智能填报 / 资产库三标签页
struct MainShell: View {
    var body: some View {
        TabView {
            WorkbenchView()
                .tabItem { Label("版本对比", systemImage: "arrow.left.arrow.right.square") }
            SmartFillView()
                .tabItem { Label("智能填报", systemImage: "text.badge.checkmark") }
            AssetLibraryView()
                .tabItem { Label("资产库", systemImage: "archivebox") }
        }
        .frame(minWidth: 1040, minHeight: 680)
    }
}

#Preview {
    MainShell()
}
