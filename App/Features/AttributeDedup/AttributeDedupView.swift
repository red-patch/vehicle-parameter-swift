import SwiftUI
import VehicleKit

// MARK: - 属性池去重页（旧版 AttributeDedup 直译）

@MainActor
@Observable
final class AttributeDedupModel {
    private(set) var fileName: String?
    private(set) var rows: [AttributeRow] = []
    private(set) var rawCount = 0
    private(set) var lastError: String?

    var dedupedCount: Int { rows.count }
    var removedCount: Int { max(0, rawCount - rows.count) }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx"), .init(filenameExtension: "xls")]
            .compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    let rows = try AttributeDedup.dedupe(url: url)
                    return rows
                }.value
                rows = parsed
                fileName = url.lastPathComponent
                // 原始条数从去重 Map 语义反推不了，这里重算：重读一遍计数
                rawCount = Self.rawRowCount(url: url) ?? parsed.count
                lastError = nil
            } catch {
                rows = []
                fileName = url.lastPathComponent
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private static func rawRowCount(url: URL) -> Int? {
        guard let sheets = try? SheetGridLoader.load(url: url),
              let grid = sheets.first?.grid else { return nil }
        guard let headerRow = grid.rows.first(where: { row in
            row.contains { $0?.jsString.trimmingCharacters(in: .whitespaces) == "属性名称" }
        }), let headerIdx = grid.rows.firstIndex(where: { $0 == headerRow }) else { return nil }
        let nameCol = headerRow.firstIndex {
            $0?.jsString.trimmingCharacters(in: .whitespaces) == "属性名称"
        } ?? -1
        var count = 0
        for i in (headerIdx + 1)..<grid.count {
            if !(grid.cell(i, nameCol)?.jsString.trimmingCharacters(in: .whitespaces) ?? "").isEmpty {
                count += 1
            }
        }
        return count
    }

    func exportCSV() {
        guard !rows.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = AttributeDedup.outputFileName(for: fileName ?? "属性池.xlsx")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AttributeDedup.csvContent(rows).write(to: url, atomically: true, encoding: .utf8)
            lastError = nil
        } catch {
            lastError = "导出失败：\(error.localizedDescription)"
        }
    }

    func clear() {
        rows = []
        fileName = nil
        rawCount = 0
    }
}

struct AttributeDedupView: View {
    @State private var model = AttributeDedupModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("商品属性数据去重").font(.title2.bold())
                Text("上传属性池 Excel 文件，按「属性名称」去重后导出「属性名称、是否必填」两列 CSV")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)

            toolbar.padding(.horizontal, 16).padding(.top, 10)

            if let error = model.lastError {
                Text(error).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }

            if model.rows.isEmpty {
                ContentUnavailableView("属性去重", systemImage: "tablecells.badge.ellipsis",
                    description: Text("请上传属性池 Excel 文件"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                stats.padding(.horizontal, 16).padding(.top, 8)
                Table(model.rows) {
                    TableColumn("序号") { row in
                        Text("\(row.id + 1)").monospacedDigit().foregroundStyle(.tertiary)
                    }.width(60)
                    TableColumn("属性名称") { row in
                        Text(row.name).lineLimit(1)
                    }
                    TableColumn("是否必填") { row in
                        Text(row.required.isEmpty ? "-" : row.required)
                            .foregroundStyle(row.required == "是" ? .green : .secondary)
                    }.width(100)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.chooseFile()
            } label: {
                Label("上传 Excel 文件", systemImage: "square.and.arrow.down.on.square")
            }
            .buttonStyle(.borderedProminent)

            if let name = model.fileName {
                Text("当前文件：\(name)").font(.callout).foregroundStyle(.secondary)
            }

            Spacer()

            if !model.rows.isEmpty {
                Button {
                    model.exportCSV()
                } label: {
                    Label("导出 CSV", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    model.clear()
                } label: {
                    Label("清空", systemImage: "trash")
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 24) {
            stat("原始数据条数", "\(model.rawCount)", color: .primary)
            stat("去重后条数", "\(model.dedupedCount)", color: .green)
            stat("去除重复", "\(model.removedCount)", color: .red)
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func stat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
        }
    }
}

#Preview {
    AttributeDedupView()
}
