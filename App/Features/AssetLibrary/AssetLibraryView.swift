import SwiftUI
import VehicleKit

/// M3 资产库：旧版资产目录直接挂载、标签管理、批量操作、v1.0 导出
struct AssetLibraryView: View {
    @State private var model = AssetLibraryModel()
    @State private var newTag = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = model.lastError {
                errorBanner(error)
            }
            HSplitView {
                sidebar
                    .frame(minWidth: 180, maxWidth: 240, maxHeight: .infinity)
                tablePane
                    .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 660)
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.chooseDirectory()
            } label: {
                Label(model.directory?.lastPathComponent ?? "挂载资产库目录",
                      systemImage: "folder.badge.gearshape")
            }
            Button {
                model.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.directory == nil)
            .help("重新扫描")

            if let status = model.statusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                TextField("新标签", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onSubmit(addTag)
                Button("批量添加标签 (\(model.selection.count))", action: addTag)
                    .disabled(model.selection.isEmpty || newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button("导出选中") { model.exportSelection() }
                .disabled(model.selection.isEmpty)
            Button("在访达中显示") { model.revealInFinder() }
                .disabled(model.directory == nil)
            Button("删除", role: .destructive) { showDeleteConfirm = true }
                .disabled(model.selection.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .confirmationDialog(
            "确定删除选中的 \(model.selection.count) 个资产文件？此操作会从磁盘删除 JSON 文件。",
            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) { model.deleteSelection() }
            Button("取消", role: .cancel) {}
        }
    }

    private func addTag() {
        model.addTagToSelection(newTag)
        newTag = ""
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.callout).lineLimit(2)
            Spacer()
            Button { model.clearError() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.red)
    }

    // MARK: 标签侧栏

    private var sidebar: some View {
        List {
            Section("标签筛选") {
                Button {
                    model.tagFilter = nil
                } label: {
                    HStack {
                        Text("全部资产")
                        Spacer()
                        Text("\(model.assets.count)").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                ForEach(model.allTags, id: \.self) { tag in
                    Button {
                        model.tagFilter = model.tagFilter == tag ? nil : tag
                    } label: {
                        HStack {
                            Text(tag)
                                .fontWeight(model.tagFilter == tag ? .semibold : .regular)
                            Spacer()
                            Text("\(countForTag(tag))").foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func countForTag(_ tag: String) -> Int {
        model.assets.filter { (model.tags[$0.fileName] ?? []).contains(tag) }.count
    }

    // MARK: 资产表

    private var tablePane: some View {
        Table(of: AssetFileInfo.self, selection: Binding(
            get: { model.selection },
            set: { model.selection = $0 }
        )) {
            TableColumn("文件名") { asset in
                Text(asset.fileName).lineLimit(1).truncationMode(.middle)
            }
            TableColumn("产品名") { asset in
                Text(asset.productName).lineLimit(1)
            }
            TableColumn("参数") { asset in
                Text("\(asset.filledParams)/\(asset.totalParams)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            TableColumn("公告号") { asset in
                Text(asset.announceNos.prefix(2).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TableColumn("车辆型号") { asset in
                Text(asset.vehicleModel ?? "—").foregroundStyle(.secondary).lineLimit(1)
            }
            TableColumn("标签") { asset in
                HStack(spacing: 4) {
                    ForEach(model.tagsFor(asset.fileName), id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            TableColumn("更新时间") { asset in
                Text(shortTime(asset.updatedAt)).foregroundStyle(.tertiary)
            }
        } rows: {
            ForEach(model.visibleAssets) { asset in
                TableRow(asset)
            }
        }
        .contextMenu(forSelectionType: String.self, menu: { selection in
            Button("在访达中显示") {
                model.selection = selection
                model.revealInFinder()
            }
            Button("重命名…") {
                guard selection.count == 1, let name = selection.first else { return }
                showRenameDialog(fileName: name)
            }
        }, primaryAction: nil)
    }

    @State private var renameTarget: String?
    @State private var renameText = ""

    private func showRenameDialog(fileName: String) {
        renameTarget = fileName
        renameText = fileName
    }

    private var renameSheet: some View {
        VStack(spacing: 12) {
            Text("重命名资产文件").font(.headline)
            TextField("新文件名", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Button("取消") { renameTarget = nil }
                Button("重命名") {
                    if let target = renameTarget {
                        model.rename(fileName: target, to: renameText)
                    }
                    renameTarget = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private func shortTime(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso
        }
        return date.formatted(date: .numeric, time: .shortened)
    }
}

#Preview {
    AssetLibraryView()
}
