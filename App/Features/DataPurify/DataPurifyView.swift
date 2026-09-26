import SwiftUI
import VehicleKit

/// M4 数据净化：可编辑参数体检（名称标准性 / 枚举一致性 / 推荐修正）+ 保存资产
struct DataPurifyView: View {
    @State private var model = DataPurifyModel()
    @State private var showSaveSheet = false
    @State private var saveName = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error = model.lastError {
                errorBanner(error)
            }
            filterBar
            Divider()
            content
        }
        .frame(minWidth: 1040, minHeight: 660)
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                model.chooseLibraryFile()
            } label: {
                Label(model.libraryFileURL?.lastPathComponent ?? "打开参数 Excel",
                      systemImage: "doc.badge.gearshape")
            }

            Picker("车型", selection: Binding(
                get: { model.selectedProduct },
                set: { model.selectedProduct = $0; model.productChanged() }
            )) {
                ForEach(model.products, id: \.self) { p in
                    Text(p).tag(p)
                }
            }
            .frame(width: 240)
            .disabled(model.products.isEmpty)

            Spacer()

            Button {
                model.addParam()
            } label: {
                Label("手动新增参数", systemImage: "plus")
            }

            Button {
                saveName = "\(model.selectedProduct ?? "未命名车型")_\(Self.todayStamp())"
                showSaveSheet = true
            } label: {
                Label("另存为", systemImage: "square.and.arrow.down")
            }
            .disabled(model.params.isEmpty)

            Button {
                if model.isExistingAsset {
                    model.saveToAsset(fileName: model.selectedProduct ?? "")
                } else {
                    saveName = "\(model.selectedProduct ?? "未命名车型")_\(Self.todayStamp())"
                    showSaveSheet = true
                }
            } label: {
                Label(model.isExistingAsset ? "覆盖原资产" : "保存至资产库",
                      systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isExistingAsset ? .orange : .green)
            .disabled(model.params.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private static func todayStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private var saveSheet: some View {
        VStack(spacing: 14) {
            Text("保存至资产库").font(.headline)
            TextField("文件名", text: $saveName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            Text("格式：v1.0 JSON（旧版可直接读回）")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { showSaveSheet = false }
                Button("保存") {
                    model.saveToAsset(fileName: saveName)
                    showSaveSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
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

    // MARK: 过滤栏

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("分组", selection: Binding(
                get: { model.filterGroup ?? "" },
                set: { model.filterGroup = $0.isEmpty ? nil : $0 }
            )) {
                Text("所有分组").tag("")
                ForEach(model.availableGroups, id: \.self) { g in
                    Text(g).tag(g)
                }
            }
            .frame(width: 150)

            TextField("搜索参数名、分组或参数值", text: $model.paramSearch)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            Picker("字段组", selection: $model.fieldGroupFilter) {
                Text("全部字段组").tag("all")
                ForEach(model.fieldGroups) { group in
                    Text(group.name).tag(group.id)
                }
            }
            .frame(width: 170)

            Button {
                model.anomalyOnly.toggle()
            } label: {
                if model.anomalyCount > 0 {
                    Label("发现异常 (\(model.anomalyCount))", systemImage: "exclamationmark.triangle")
                } else {
                    Label("完全合规", systemImage: "checkmark.seal")
                }
            }
            .buttonStyle(.bordered)
            .tint(model.anomalyOnly ? .accentColor : (model.anomalyCount > 0 ? .orange : .secondary))

            Spacer()
            Text("\(model.filteredParams.count)/\(model.params.count) 行")
                .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: 参数表（可编辑行）

    private var content: some View {
        List {
            ForEach(model.filteredParams) { param in
                PurifyRowView(param: param, model: model)
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.params.isEmpty {
                ContentUnavailableView("数据净化", systemImage: "checklist",
                    description: Text("打开参数 Excel 并选择车型后开始体检"))
            }
        }
    }
}

/// 单行：分组 / 参数名（含推荐 popover）/ 参数值（枚举下拉或文本）
struct PurifyRowView: View {
    let param: PurifiedParam
    let model: DataPurifyModel
    @State private var showFixes = false
    @State private var manualMode = false

    var body: some View {
        HStack(spacing: 8) {
            // 分组
            TextField("分组", text: Binding(
                get: { param.group },
                set: { model.updateParam(id: param.id, group: $0) }
            ))
            .textFieldStyle(.plain)
            .frame(width: 110)

            // 参数名 + 警告
            HStack(spacing: 4) {
                TextField("参数名", text: Binding(
                    get: { param.name },
                    set: { model.updateParam(id: param.id, name: $0) }
                ))
                .textFieldStyle(.plain)
                .fontWeight(.medium)

                if !param.isNameStandard, !param.name.isEmpty {
                    Button {
                        showFixes.toggle()
                    } label: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showFixes) {
                        fixesPopover
                    }
                }
            }
            .frame(minWidth: 220, alignment: .leading)

            // 参数值
            HStack(spacing: 6) {
                if param.hasEnums && !manualMode {
                    Picker("", selection: Binding(
                        get: { param.value },
                        set: { model.updateParam(id: param.id, value: $0) }
                    )) {
                        Text("").tag("")
                        ForEach(param.enums, id: \.self) { e in
                            Text(e).tag(e)
                        }
                    }
                    .labelsHidden()
                } else {
                    TextField("输入数值", text: Binding(
                        get: { param.value },
                        set: { model.updateParam(id: param.id, value: $0) }
                    ))
                    .textFieldStyle(.plain)
                }

                if param.isEnumMismatch {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .help("“\(param.value)”不在标准字典内")
                }
                if param.hasEnums {
                    Button {
                        manualMode.toggle()
                    } label: {
                        Image(systemName: manualMode ? "list.bullet.rectangle" : "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(manualMode ? "切换为标准选择" : "手动输入")
                }
            }
            .frame(minWidth: 260, alignment: .leading)

            if let stamp = param.updatedAt {
                Text("已于 \(stamp) 手动更新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 130, alignment: .leading)
            } else {
                Text("").frame(width: 130)
            }

            Button(role: .destructive) {
                model.deleteParam(id: param.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var fixesPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("推荐的标准字段名").font(.headline)
            if param.nameFixes.isEmpty {
                Text("无匹配的推荐字段名").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(param.nameFixes, id: \.self) { fix in
                    Button(fix) {
                        model.updateParam(id: param.id, name: fix)
                        showFixes = false
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
    }
}

#Preview {
    DataPurifyView()
}
