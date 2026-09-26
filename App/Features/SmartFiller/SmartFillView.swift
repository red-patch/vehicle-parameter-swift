import SwiftUI
import VehicleKit

/// M2 智能填报：基准库 → 需求文本 → 匹配结果（可修正）→ 车上云模板导出
struct SmartFillView: View {
    @State private var model = SmartFillModel()

    var body: some View {
        HSplitView {
            // 左栏：基准库 + 需求文本
            leftPane
                .frame(minWidth: 320, maxWidth: 460, maxHeight: .infinity)
            // 右栏：匹配结果
            rightPane
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 660)
        .onAppear {
            if model.libraryFileURL == nil { model.chooseLibraryFile() }
        }
    }

    // MARK: 左栏

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.chooseLibraryFile()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.icloud")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.libraryFileURL?.lastPathComponent ?? "选择基准库文件")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let summary = model.librarySummary {
                            Text(summary).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("包含待匹配参数库的 Excel").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !model.libraryProducts.isEmpty {
                Picker("产品", selection: Binding(
                    get: { model.selectedProduct },
                    set: { model.selectedProduct = $0; model.productChanged() }
                )) {
                    ForEach(model.libraryProducts, id: \.name) { product in
                        productLabel(product).tag(product.name)
                    }
                }
                .labelsHidden()
            }

            Text("需求参数（每行一个，输入即匹配）")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: Binding(
                get: { model.requirementsText },
                set: { model.requirementsText = $0; model.requirementsTextChanged() }
            ))
            .font(.system(size: 12))
            .monospaced()
            .border(Color(nsColor: .separatorColor).opacity(0.5))
            .frame(maxHeight: .infinity)

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }
        }
        .padding(12)
    }

    private func productLabel(_ product: ProductConfidence) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Self.levelColor(product.level))
                .frame(width: 7, height: 7)
            Text(product.name)
                .lineLimit(1)
            Text("\(product.paramCount)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private static func levelColor(_ level: ProductConfidence.Level) -> Color {
        switch level {
        case .high: .green
        case .medium: .orange
        case .low: .red
        }
    }

    // MARK: 右栏

    private var rightPane: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if model.items.isEmpty {
                emptyState
            } else {
                MatchResultGrid(model: model, items: model.filteredItems)
            }
            Divider()
            actionBar
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            TextField("搜索（换行分隔多个关键词）", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Picker("匹配度", selection: $model.confidenceFilter) {
                ForEach(SmartFillModel.ConfidenceFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .frame(width: 130)

            Picker("状态", selection: $model.statusFilter) {
                ForEach(SmartFillModel.StatusFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .frame(width: 110)

            Button {
                model.enumMismatchOnly.toggle()
            } label: {
                Label("枚举异常 \(model.enumMismatchItems.count)", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.bordered)
            .tint(model.enumMismatchOnly ? .accentColor : .secondary)
            .disabled(model.enumMismatchItems.isEmpty)

            Spacer()
            Text("\(model.filteredItems.count)/\(model.items.count) 行")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("匹配结果", systemImage: "text.badge.checkmark")
        } description: {
            Text("选择基准库并输入需求参数后\n匹配结果将在此展示")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("复制填报结果 (CSV)") { model.copyCSV() }
                .disabled(model.filteredItems.isEmpty)

            if !model.enumMismatchItems.isEmpty {
                Button("复制枚举异常字段 (\(model.enumMismatchItems.count))") {
                    model.copyEnumMismatches()
                }
            }

            Spacer()

            Button {
                model.exportVehicleCloud()
            } label: {
                Label("车上云系统模板导出", systemImage: "square.and.arrow.up.on.square")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.filteredItems.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    SmartFillView()
}
