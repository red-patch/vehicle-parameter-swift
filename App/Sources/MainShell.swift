import SwiftUI
import VehicleKit

/// 主窗口壳 —— M4：版本对比 / 智能填报 / 资产库 / 数据净化 / 属性去重 / 公告查询
struct MainShell: View {
    var body: some View {
        TabView {
            WorkbenchView()
                .tabItem { Label("版本对比", systemImage: "arrow.left.arrow.right.square") }
            SmartFillView()
                .tabItem { Label("智能填报", systemImage: "text.badge.checkmark") }
            AssetLibraryView()
                .tabItem { Label("资产库", systemImage: "archivebox") }
            DataPurifyView()
                .tabItem { Label("数据净化", systemImage: "checklist") }
            AttributeDedupView()
                .tabItem { Label("属性去重", systemImage: "tablecells.badge.ellipsis") }
            AnnouncementQueryView()
                .tabItem { Label("公告查询", systemImage: "globe.asia.australia") }
        }
        .frame(minWidth: 1040, minHeight: 680)
    }
}

#Preview {
    MainShell()
}
