import AppKit
import Observation
import VehicleKit

// MARK: - 数据净化视图模型（旧版 DataPurifyView 域侧状态）

@MainActor
@Observable
final class DataPurifyModel {
    var libraryFileURL: URL?
    var selectedProduct: String?

    private(set) var librarySheet: SheetData?
    private(set) var products: [String] = []
    private(set) var params: [PurifiedParam] = []
    private(set) var fieldGroups: [FieldGroupConfig] = []
    private(set) var lastError: String?
    private(set) var statusText: String?

    // 过滤状态（旧版 FilterBar）
    var filterGroup: String?
    var paramSearch = ""
    var anomalyOnly = false
    var fieldGroupFilter = "all"

    let purifier: Purifier
    /// 资产库目录（与资产库页共享 UserDefaults 记忆）
    var assetDirectory: URL? {
        if let path = UserDefaults.standard.string(forKey: "assetLibraryPath") {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    /// 是否已有同名资产（覆盖 / 另存提示）
    private(set) var isExistingAsset = false
    /// 工作副本的原始 VehicleParameter（保存时转换）
    private var rawParams: [VehicleParameter] = []

    init() {
        purifier = Purifier(dictionary: EnumDictionary.loadBundled())
        fieldGroups = FieldGroups.load(directory: assetDirectory)
    }

    // MARK: 数据源

    func chooseLibraryFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryFileURL = url
        Task {
            do {
                let sheet = try await Task.detached(priority: .userInitiated) {
                    try ExcelParser.parse(url: url)
                }.value
                var counts: [String: Int] = [:]
                var order: [String] = []
                for p in sheet.data {
                    let name = p.productName ?? sheet.fileName
                    if counts[name] == nil { order.append(name) }
                    counts[name, default: 0] += 1
                }
                librarySheet = sheet
                products = order
                selectedProduct = order.first
                statusText = "\(sheet.fileName)：\(order.count) 产品"
                loadProduct()
            } catch {
                lastError = "\(url.lastPathComponent)：\(error.localizedDescription)"
            }
        }
    }

    func productChanged() {
        loadProduct()
    }

    private func loadProduct() {
        guard let librarySheet, let selectedProduct else {
            params = []
            return
        }
        rawParams = librarySheet.data.filter { ($0.productName ?? librarySheet.fileName) == selectedProduct }
        params = purifier.purify(rawParams)
        // 同名资产检测
        if let dir = assetDirectory {
            let candidates = ["\(selectedProduct).json", selectedProduct]
            isExistingAsset = candidates.contains {
                FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
            }
        }
    }

    // MARK: 编辑操作

    func updateParam(id: String, group: String? = nil, name: String? = nil, value: String? = nil) {
        guard let idx = rawParams.firstIndex(where: { $0.id == id }) else { return }
        let stamp = Purifier.nowStamp()
        if let group { rawParams[idx].group = group }
        if let name { rawParams[idx].name = name }
        if let value { rawParams[idx].value = .string(value) }
        rawParams[idx].updatedAt = stamp
        // 重算该行检测状态（其余行名称未变，无需整体重算）
        let updated = purifier.purify([rawParams[idx]])[0]
        if let pIdx = params.firstIndex(where: { $0.id == id }) {
            params[pIdx] = updated
        }
    }

    func deleteParam(id: String) {
        rawParams.removeAll { $0.id == id }
        params.removeAll { $0.id == id }
    }

    func addParam() {
        let newParam = VehicleParameter(
            id: "new-\(Int(Date().timeIntervalSince1970 * 1000))",
            group: "新增参数", name: "", value: .string(""),
            productName: selectedProduct, updatedAt: Purifier.nowStamp())
        rawParams.insert(newParam, at: 0)
        params.insert(purifier.purify([newParam])[0], at: 0)
    }

    // MARK: 过滤（旧版 filteredParams 三级衍生）

    var availableGroups: [String] {
        Array(Set(params.map(\.group))).sorted()
    }

    var filteredParams: [PurifiedParam] {
        let selectedFieldGroup = fieldGroups.first { $0.id == fieldGroupFilter }
        let keyword = paramSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return params.filter { p in
            if let filterGroup, p.group != filterGroup { return false }
            if let selectedFieldGroup, !selectedFieldGroup.fields.contains(p.name) { return false }
            if !keyword.isEmpty {
                let matchName = p.name.lowercased().contains(keyword)
                let matchGroup = p.group.lowercased().contains(keyword)
                let matchValue = p.value.lowercased().contains(keyword)
                if !matchName && !matchGroup && !matchValue { return false }
            }
            if anomalyOnly { return p.isAnomaly }
            return true
        }
    }

    var anomalyCount: Int { params.filter(\.isAnomaly).count }

    // MARK: 保存资产（v1.0 契约）

    func saveToAsset(fileName: String) {
        guard let directory = assetDirectory, let selectedProduct else {
            lastError = "请先在「资产库」页挂载资产库目录"
            return
        }
        let store = AssetStore(directory: directory)
        do {
            let finalName = fileName.hasSuffix(".json") ? fileName : "\(fileName).json"
            _ = try store.save(fileName: finalName, productName: selectedProduct,
                               parameters: Purifier.toParameters(params))
            isExistingAsset = store.scan().contains { $0.fileName == finalName }
            statusText = "已保存资产：\(finalName)"
            lastError = nil
        } catch {
            lastError = "保存失败：\(error.localizedDescription)"
        }
    }

    func clearError() { lastError = nil }
}
