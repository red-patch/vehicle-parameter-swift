import SwiftUI

/// 参数网格 —— NSTableView 的 NSViewRepresentable 封装（核心可编辑表格组件）。
/// M0 占位：M1 落地只读 diff 视图（四态着色），M2 起按 枚举下拉 → 文本 → 修复入口 渐进上线编辑器。
struct ParameterGrid: View {
    var body: some View {
        ContentUnavailableView(
            "ParameterGrid",
            systemImage: "tablecells",
            description: Text("M1 里程碑落地：只读 diff 表格")
        )
    }
}

#Preview {
    ParameterGrid()
        .frame(width: 480, height: 320)
}
