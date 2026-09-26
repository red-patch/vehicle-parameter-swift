import SwiftUI
import VehicleKit

/// 主窗口壳 —— M0 占位，随里程碑逐个接入 Feature（DiffViewer / SmartFiller / Workbench…）
struct MainShell: View {
    var body: some View {
        ContentUnavailableView {
            Label("车辆参数工具", systemImage: "car.2.fill")
        } description: {
            Text("macOS 原生版 · M0 脚手架\n域层 VehicleKit 就绪（资产格式 v\(AssetDocument.formatVersion)）")
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

#Preview {
    MainShell()
}
