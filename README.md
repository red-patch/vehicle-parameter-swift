# vehicle-parameter-swift

> 版本：v0.1（M0 脚手架）· 2026-09-26

车辆整车参数配置与管理工具的 **macOS 原生重写版**。旧版（[/Users/ethan/code/软件开发/vehicle-parameter](../vehicle-parameter)，Tauri 2 + React 19）继续维护并服务 Windows 用户；本项目仅面向 macOS，目标是把性能与交互体验做到原生级极致。

## 定位与目标

- **目标平台**：macOS 14+，Apple Silicon 优先，Swift 6
- **性能目标**：
  - 空闲内存 < 40MB（旧版 Tauri 约 100-250MB）
  - 冷启动 < 0.5s（旧版约 1.5-3s）
  - 万行级参数表格 120Hz 满帧滚动、零可感击键延迟
  - 中文 IME 组合态由系统保证（NSTableView + NSTextField 原生编辑体系）
- **与旧仓库的关系**：
  - 重写期间旧版继续发布（Windows 续命），功能以旧版 docs/PRD.md（V1.0-V4.4，14 个版本）为对齐基准
  - **资产库 JSON 格式保持互通**：旧版导出的资产文件可直接导入新版（格式见下方"数据兼容"）

## 技术栈总览

| 层 | 技术 | 说明 |
|---|---|---|
| UI 外壳 | SwiftUI | 导航/侧栏/设置/菜单栏/标签页 |
| 参数网格 | NSTableView（NSViewRepresentable 包装） | 可编辑单元格、视图复用、diff 着色——应用 80% 使用时长所在 |
| 数据层 | GRDB / SQLite | 数据池/资产库/会话持久化（替代旧版 zustand + localStorage） |
| Excel 读 | CoreXLSX | 纯 Swift 解析 .xlsx |
| Excel 写 | libxlsxwriter（SPM 接 C 库） | 导出 xlsx |
| 模糊匹配 | fuse-swift | Fuse.js 官方 Swift 移植，阈值语义与旧版对齐 |
| PDF 报告 | PDFKit | 矢量文字，优于旧版 jsPDF |
| 自动更新 | Sparkle 2 | |
| 工程管理 | XcodeGen | 声明式 project.yml，agent 友好 |

## 数据兼容

旧版资产文件格式（`assetManager.ts` 的 `AssetFileFormat`，版本号 `1.0`）：

```json
{
  "version": "1.0",
  "productName": "…",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601",
  "parameters": [ { "id": "…", "group": "…", "name": "…", "value": "…", "productName": "…" } ]
}
```

配套元数据文件：`_asset_tags.json`（标签分组）、`custom_bid_field_mappings.json`（多车取数映射）。新版 M3 里程碑实现同格式读写。

## 当前状态

**M0 完成并通过全量验收（2026-09-26）。**

- `Package.swift`：VehicleKit（Swift 6 · macOS 14+），CoreXLSX 0.14.x + fuse-swift 1.4.x 已接入
- `VehicleKit/`：核心模型 `VehicleParameter`（旧版 string|number 双态桥接）与 `AssetDocument`（资产格式 v1.0 兼容读写）+ XCTest
- `project.yml` → `VehicleParameter.xcodeproj`：App 目标（SwiftUI 空窗口壳）挂本地 VehicleKit 包与 GRDB 7（数据层，M3 启用），签名占位 Automatic
- CI：`.github/workflows/ci.yml`（swift build/test + xcodegen generate + 免签名 xcodebuild）
- 验收记录：`xcodegen generate` ✓ · `swift build` ✓ · `swift test` 12/12 ✓ · App 构建+启动运行 ✓（Xcode 16 · Swift 6.1）
- 已知差异：Xcode 16 JSONEncoder 的漂亮打印与 JSON.stringify 空白/字段序不逐字节一致（语义互通无损）；若 M3 golden 需逐字节对齐再实现专用 writer

架构蓝图见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，里程碑与验收标准见 [docs/MILESTONES.md](docs/MILESTONES.md)。

## 许可

待定（建议与旧版一致的 MIT）。
