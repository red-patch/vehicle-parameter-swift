import AppKit
import SwiftUI
import VehicleKit

// MARK: - 公告查询页（旧版 AnnouncementQuery 直译：openURL + 书签粘贴导入）

@MainActor
@Observable
final class AnnouncementQueryModel {
    var announcementNo = ""
    var importJSON = ""
    private(set) var imported: SheetData?
    private(set) var lastMessage: String?
    private(set) var isError = false

    func openQuery() {
        guard !announcementNo.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = AnnouncementQuery.queryURL(for: announcementNo) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyBookmarklet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AnnouncementQuery.bookmarkletCode, forType: .string)
        lastMessage = "书签脚本已复制，粘贴到浏览器书签后，在工信部参数详情页点击即可复制数据"
        isError = false
    }

    func importFromClipboardJSON() {
        do {
            let sheet = try AnnouncementQuery.parseImport(
                importJSON,
                announcementNo: announcementNo.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "工信部数据导入" : announcementNo)
            imported = sheet
            lastMessage = "成功导入 \(sheet.data.count) 条参数"
            isError = false
        } catch {
            lastMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isError = true
        }
    }

    /// 设为版本对比的新版本（切到公告对比模式）
    @MainActor func useAsCompareTarget() {
        guard let sheet = imported else { return }
        UserDefaults.standard.set(sheet.fileName, forKey: "miitTargetFileName")
        NotificationCenter.default.post(name: .miitDataImported, object: sheet)
        lastMessage = "已切换到「版本对比」，并启用公告对比模式"
        isError = false
    }

    /// 保存为资产
    func saveToAsset() {
        guard let sheet = imported else { return }
        let directory: URL?
        if let path = UserDefaults.standard.string(forKey: "assetLibraryPath") {
            directory = URL(fileURLWithPath: path)
        } else {
            directory = nil
        }
        guard let directory else {
            lastMessage = "请先在「资产库」页挂载资产库目录"
            isError = true
            return
        }
        do {
            let store = AssetStore(directory: directory)
            let name = sheet.fileName.hasSuffix(".json") ? sheet.fileName : "\(sheet.fileName).json"
            _ = try store.save(fileName: name, productName: sheet.fileName, parameters: sheet.data)
            lastMessage = "已保存资产：\(name)"
            isError = false
        } catch {
            lastMessage = "保存失败：\(error.localizedDescription)"
            isError = true
        }
    }
}

extension Notification.Name {
    /// 公告数据导入完成，供版本对比页接管（携带 SheetData）
    static let miitDataImported = Notification.Name("miitDataImported")
}

struct AnnouncementQueryView: View {
    @State private var model = AnnouncementQueryModel()

    var body: some View {
        HSplitView {
            leftPane.frame(minWidth: 380, maxWidth: 480, maxHeight: .infinity)
            rightPane.frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private var leftPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. 查询
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("第一步：查询公告", systemImage: "magnifyingglass")
                            .font(.headline)
                        Text("输入公告号，打开工信部查询页面")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            TextField("公告号，如 JHC6507BEVR2", text: $model.announcementNo)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { model.openQuery() }
                            Button("打开查询") { model.openQuery() }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.announcementNo.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(4)
                }

                // 2. 书签
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("第二步：安装书签脚本", systemImage: "bookmark")
                            .font(.headline)
                        Text("在浏览器中新建书签，地址粘贴以下脚本；在工信部「参数详情页」点击该书签，参数将被复制到剪贴板")
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            model.copyBookmarklet()
                        } label: {
                            Label("复制书签脚本", systemImage: "doc.on.doc")
                        }
                    }
                    .padding(4)
                }

                // 3. 导入
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("第三步：粘贴导入", systemImage: "doc.badge.plus")
                            .font(.headline)
                        TextEditor(text: $model.importJSON)
                            .font(.system(size: 11).monospaced())
                            .border(Color(nsColor: .separatorColor))
                            .frame(height: 160)
                        Button("解析导入") { model.importFromClipboardJSON() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.importJSON.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(4)
                }

                if let message = model.lastMessage {
                    Label(message, systemImage: model.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(model.isError ? .red : .green)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var rightPane: some View {
        if let sheet = model.imported {
            VStack(spacing: 0) {
                HStack {
                    Text("导入预览：\(sheet.fileName)")
                        .font(.headline)
                    Text("\(sheet.data.count) 条").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.useAsCompareTarget()
                    } label: {
                        Label("设为对比新版本", systemImage: "arrow.left.arrow.right")
                    }
                    Button {
                        model.saveToAsset()
                    } label: {
                        Label("保存至资产库", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List(sheet.data, id: \.id) { p in
                    HStack(spacing: 10) {
                        Text(p.group)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 90, alignment: .leading)
                        Text(p.name)
                            .fontWeight(.medium)
                            .frame(width: 180, alignment: .leading)
                        Text(p.displayValue)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 1)
                }
                .listStyle(.plain)
            }
        } else {
            ContentUnavailableView("导入预览", systemImage: "doc.text.magnifyingglass",
                description: Text("按左侧三步操作后，导入的工信部参数将在此展示"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    AnnouncementQueryView()
}
