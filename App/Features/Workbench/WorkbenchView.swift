import SwiftUI
import VehicleKit

/// M1 工作台：双 Excel 上传 → 解析 → 四态对比 → 只读表格 + PDF 报告
struct WorkbenchView: View {
    @State private var model = WorkbenchModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = model.lastError {
                errorBanner(error)
            }
            if model.diff == nil {
                emptyState
            } else {
                content
            }
        }
        .frame(minWidth: 980, minHeight: 620)
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 12) {
            fileButton(
                title: "基准文件",
                icon: "doc.badge.clock",
                name: model.baseFileURL?.lastPathComponent,
                summary: model.baseSummary
            ) {
                model.chooseBaseFile()
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
            fileButton(
                title: "对比文件",
                icon: "doc.badge.plus",
                name: model.targetFileURL?.lastPathComponent,
                summary: model.targetSummary
            ) {
                model.chooseTargetFile()
            }

            Divider()
                .frame(height: 36)

            Picker("模式", selection: Binding(
                get: { model.mode },
                set: { model.mode = $0; model.modeChanged() }
            )) {
                Text("内容对比").tag(CompareMode.content)
                Text("公告对比").tag(CompareMode.miit)
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer()

            if !model.countsText.isEmpty {
                Text(model.countsText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Button {
                model.exportPDF()
            } label: {
                Label("导出 PDF 报告", systemImage: "doc.richtext")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExportPDF)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func fileButton(
        title: String, icon: String, name: String?, summary: String?, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name ?? "选择 \(title)")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(minWidth: 190, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.callout)
                .lineLimit(3)
            Spacer()
            Button {
                model.clearError()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.red)
    }

    // MARK: 空态

    private var emptyState: some View {
        ContentUnavailableView {
            Label("版本对比", systemImage: "arrow.left.arrow.right.square")
        } description: {
            Text("选择两个 Excel 文件开始对比\n支持纵向参数表、键值对表与横向产品准入导出格式")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 结果区

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("筛选", selection: Binding(
                    get: { model.filter },
                    set: { model.filter = $0 }
                )) {
                    ForEach(DiffFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue + countSuffix(filter))
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 420)

                Spacer()
                Text("\(model.rows.count) 行")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ParameterGrid(rows: model.rows)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func countSuffix(_ filter: DiffFilter) -> String {
        guard let diff = model.diff else { return "" }
        let count: Int
        switch filter {
        case .all: return ""
        case .added: count = diff.added.count
        case .removed: count = diff.removed.count
        case .modified: count = diff.modified.count
        case .unchanged: count = diff.unchanged.count
        }
        return " \(count)"
    }
}

#Preview {
    WorkbenchView()
}
