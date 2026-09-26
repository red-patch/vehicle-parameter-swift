import SwiftUI
import VehicleKit

/// 主窗口壳 —— M2：工作台（版本对比）+ 智能填报双标签页
struct MainShell: View {
    var body: some View {
        TabView {
            WorkbenchView()
                .tabItem { Label("版本对比", systemImage: "arrow.left.arrow.right.square") }
            SmartFillView()
                .tabItem { Label("智能填报", systemImage: "text.badge.checkmark") }
        }
        .frame(minWidth: 1040, minHeight: 680)
    }
}

#Preview {
    MainShell()
}
