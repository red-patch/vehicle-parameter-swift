import SwiftUI
import VehicleKit

/// 主窗口壳 —— M1：工作台（双文件版本对比）；后续里程碑接入更多 Feature
struct MainShell: View {
    var body: some View {
        WorkbenchView()
            .frame(minWidth: 1000, minHeight: 660)
    }
}

#Preview {
    MainShell()
}
