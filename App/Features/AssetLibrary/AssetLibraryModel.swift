import AppKit
import Observation
import VehicleKit

// MARK: - 资产库视图模型（目录挂载 + 扫描 + 标签 + 批量操作）

@MainActor
@Observable
final class AssetLibraryModel {
    private(set) var directory: URL?
    private(set) var assets: [AssetFileInfo] = []
    private(set) var tags: [String: [String]] = [:]
    private(set) var tagGroups: AssetTagGroupsConfig = .default
    private(set) var lastError: String?
    private(set) var statusText: String?

    /// 表格多选（fileName 集合）
    var selection: Set<String> = []
    /// 标签筛选（空 = 全部）
    var tagFilter: String?

    /// SQLite 缓存（Application Support）
    private var database: AssetDatabase?

    var visibleAssets: [AssetFileInfo] {
        guard let tagFilter else { return assets }
        return assets.filter { (tags[$0.fileName] ?? []).contains(tagFilter) }
    }

    var allTags: [String] {
        Array(Set(tags.values.flatMap { $0 })).sorted()
    }

    init() {
        // 记忆上次挂载的目录（窗口状态记忆的 M3 最小形态）
        if let path = UserDefaults.standard.string(forKey: "assetLibraryPath") {
            mount(directory: URL(fileURLWithPath: path), persist: false)
        }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = support.appendingPathComponent("VehicleParameter", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            database = try? AssetDatabase(path: dir.appendingPathComponent("assets.db").path)
        }
    }

    // MARK: 挂载与扫描

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择资产库目录（可直接挂载旧版导出的资产目录）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mount(directory: url, persist: true)
    }

    func mount(directory url: URL, persist: Bool) {
        directory = url
        if persist {
            UserDefaults.standard.set(url.path, forKey: "assetLibraryPath")
        }
        rescan()
    }

    func rescan() {
        guard let directory else { return }
        let store = AssetStore(directory: directory)
        assets = store.scan()
        tags = store.loadTags()
        tagGroups = store.loadTagGroups()
        statusText = "已挂载：\(assets.count) 个资产 · \(tags.count) 个带标签"
        syncToDatabase(store: store)
    }

    /// 目录扫描结果 upsert 进 SQLite（架构蓝图 §3；导出仍以目录 JSON 为准）
    private func syncToDatabase(store: AssetStore) {
        guard let database, let directory else { return }
        let snapshot = assets  // MainActor 上拷贝快照
        Task.detached(priority: .utility) {
            let records: [(AssetFileInfo, Data)] = snapshot.compactMap { info in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent(info.fileName)),
                      let doc = try? AssetDocument.decode(from: data),
                      let encoded = try? JSONEncoder().encode(doc.parameters) else {
                    return nil
                }
                return (info, encoded)
            }
            try? database.upsertAssets(records)
        }
    }

    // MARK: 标签操作

    func tagsFor(_ fileName: String) -> [String] {
        tags[fileName] ?? []
    }

    func addTagToSelection(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let directory else { return }
        let store = AssetStore(directory: directory)
        do {
            for fileName in selection {
                var current = tags[fileName] ?? []
                guard !current.contains(trimmed) else { continue }
                current.append(trimmed)
                try store.setTags(fileName: fileName, AssetStore.normalizeTagList(current))
            }
            tags = store.loadTags()
        } catch {
            lastError = "标签写入失败：\(error.localizedDescription)"
        }
    }

    func removeTag(_ tag: String, from fileName: String) {
        guard let directory else { return }
        let store = AssetStore(directory: directory)
        do {
            var current = tags[fileName] ?? []
            current.removeAll { $0 == tag }
            try store.setTags(fileName: fileName, current)
            tags = store.loadTags()
        } catch {
            lastError = "标签写入失败：\(error.localizedDescription)"
        }
    }

    // MARK: 资产操作

    func deleteSelection() {
        guard let directory, !selection.isEmpty else { return }
        let store = AssetStore(directory: directory)
        var deleted = 0
        for fileName in selection {
            do {
                try store.delete(fileName: fileName)
                deleted += 1
            } catch {
                lastError = "删除 \(fileName) 失败：\(error.localizedDescription)"
            }
        }
        selection.removeAll()
        rescan()
        statusText = "已删除 \(deleted) 个资产"
    }

    func rename(fileName: String, to newName: String) {
        guard let directory else { return }
        let store = AssetStore(directory: directory)
        do {
            _ = try store.rename(oldFileName: fileName, newFileName: newName)
            rescan()
        } catch {
            lastError = "重命名失败：\(error.localizedDescription)"
        }
    }

    /// 批量导出选中资产到目标目录（写回 v1.0 格式，保证互通）
    func exportSelection() {
        guard let directory, !selection.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择导出目标目录（导出旧版可用的 v1.0 JSON）"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        let source = AssetStore(directory: directory)
        let targetStore = AssetStore(directory: target)
        var exported = 0
        for fileName in selection {
            do {
                let sheet = try source.load(fileName: fileName)
                let productName = sheet.data.first?.productName ?? fileName
                _ = try targetStore.save(fileName: fileName, productName: productName, parameters: sheet.data)
                exported += 1
            } catch {
                lastError = "导出 \(fileName) 失败：\(error.localizedDescription)"
            }
        }
        statusText = "已导出 \(exported) 个资产到 \(target.lastPathComponent)"
    }

    func revealInFinder() {
        guard let directory else { return }
        let urls = selection.compactMap { name in
            let url = directory.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [directory] : urls)
    }

    func loadAsSheet(fileName: String) -> SheetData? {
        guard let directory else { return nil }
        return try? AssetStore(directory: directory).load(fileName: fileName)
    }

    func clearError() {
        lastError = nil
    }
}
