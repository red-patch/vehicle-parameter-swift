# vehicle-parameter-swift

> 版本：v0.3（M2 智能填报）· 2026-09-26

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

**M2 智能填报完成并通过全量验收（2026-09-26）。M0 / M1 已于同日验收。**

### M2 交付

- **VehicleKit 域层**：
  - `SmartFiller`：findMatches（阈值 0.4 + 置信度 exact 1.0 / normalized 0.95 / alias 0.9 / fuzzy 1-score）、手动值语义（显式空值固化）、quickFix 推荐（Fuse 0.6 无扩展搜索、排除当前项、前 3）、枚举异常检测、车上云行数据
  - `EnumDictionary`：内置 686 属性枚举字典（attribute_values.txt），标准化名查找、custom_enums.json 覆写、HTML 污染防护
  - `ProductConfidenceEvaluator`：黑名单/参数量/名称特征评分 → 三档置信度（产品选择器用）
  - `XlsxWriter`：libxlsxwriter C 互操作（独立 XlsxWriterShim 模块隔离），车上云模板导出（sheet「产品准入导入模版」、两列字符串、列宽 30/40，与旧版 Rust export_xlsx 同格式）
- **UI**：SmartFiller 功能页（基准库选择含产品置信度标记、需求文本输入即匹配 500ms 去抖、MatchResultGrid 可编辑表格：枚举下拉（含推荐值）→ 手动文本双模式切换、匹配度三色、枚举异常警告、搜索/匹配度/状态/枚举异常四重过滤、CSV 复制、车上云模板导出）
- **Golden 测试**（46 例全绿）：匹配结果 19 项需求 × 326 库参数逐项一致（含置信度）、导出-读回逐格一致、双栈交叉验证（libxlsxwriter 写 / CoreXLSX 读）
- **关键决策**：libxlsxwriter 走 Homebrew + systemLibrary 模块封装（`brew install libxlsxwriter`），Apple Silicon 优先（ARCHS=arm64）；`workbook_close()` 内部释放 workbook，重复 free 会间歇堆崩溃；Xcode 26 新版 Foundation JSONEncoder 键序随机化（语义无损）

### M1 交付

- **VehicleKit 域层**（旧版直译，语义逐条对齐）：
  - `ExcelParser`：纵向 / 键值对 / 横向（产品准入导出）三格式自动识别，跨行表头检测、分组 Fill-Down、百分比还原、跨 sheet 单产品合并、诊断信息
  - `Comparator`：content / miit 双模式四态对比（added / removed / modified / unchanged）
  - `MatchingEngine`：四级匹配（exact 0 / normalized 0.1 / alias 0.1-0.2 / fuzzy ≤0.3）+ 60 组别名词库（有序）
  - `FuseSearch`：fuse.js 7.1.0 逐行为移植（UTF-16 索引、UInt32 位掩码、扩展搜索语法、字段范数打分）——fuse-swift 打分语义有偏差，不能用于 golden 契约
  - `SheetRows`：CoreXLSX + ZIPFoundation + 自研 XMLParser/原始提取，与 SheetJS sheet_to_json 同构（含 CRLF 保留、列跨度收敛）
- **UI**：Workbench（双文件上传 → 四态对比 → 筛选）+ ParameterGrid（NSTableView 只读、四态着色、视图复用）+ PDF 报告导出（CGContext + CoreText 矢量文字）
- **Golden 测试**：
  - 解析：14 个真实/合成样本全量参数逐项一致 + SHA256 摘要
  - 对比：3 对文件 × 2 模式四态计数与全量清单逐项一致（ditie +0/-0/~5/=339 等）
  - Fuse：38 组查询分数级对齐（索引 + 分数，1e-9 精度）
  - 性能：demo1（7 sheet / 1631 参数 / 117KB）解析 0.14s < 1s 预算

### 关键实现决策（M1）

- CoreXLSX 的 XMLCoder 解码万格级横向 sheet 需 2s+ → worksheet 改用 Foundation XMLParser（17 倍提速）
- CoreXLSX 的严格 SchemaType 对 WPS/SheetJS 非标关系类型（woinfos、sheetMetadata）解码失败 → 关系解析自研
- XML 规范化会把共享字符串中的 \r\n 归一为 \n → 共享字符串从 zip 原始 XML 提取（保留 CRLF）
- golden 基准由旧版真实代码（vite-node 跑 `../vehicle-parameter` 源码）导出，随仓库提交，CI 可全量复验

CI：`.github/workflows/ci.yml`（brew libxlsxwriter + swift build/test + xcodegen + 免签名 xcodebuild arm64）。

架构蓝图见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，里程碑与验收标准见 [docs/MILESTONES.md](docs/MILESTONES.md)。

- **VehicleKit 域层**（旧版直译，语义逐条对齐）：
  - `ExcelParser`：纵向 / 键值对 / 横向（产品准入导出）三格式自动识别，跨行表头检测、分组 Fill-Down、百分比还原、跨 sheet 单产品合并、诊断信息
  - `Comparator`：content / miit 双模式四态对比（added / removed / modified / unchanged）
  - `MatchingEngine`：四级匹配（exact 0 / normalized 0.1 / alias 0.1-0.2 / fuzzy ≤0.3）+ 60 组别名词库（有序）
  - `FuseSearch`：fuse.js 7.1.0 逐行为移植（UTF-16 索引、UInt32 位掩码、扩展搜索语法、字段范数打分）——fuse-swift 打分语义有偏差，不能用于 golden 契约
  - `SheetRows`：CoreXLSX + ZIPFoundation + 自研 XMLParser/原始提取，与 SheetJS sheet_to_json 同构（含 CRLF 保留、列跨度收敛）
- **UI**：Workbench（双文件上传 → 四态对比 → 筛选）+ ParameterGrid（NSTableView 只读、四态着色、视图复用）+ PDF 报告导出（CGContext + CoreText 矢量文字）
- **Golden 测试**（37 例全绿）：
  - 解析：14 个真实/合成样本全量参数逐项一致 + SHA256 摘要
  - 对比：3 对文件 × 2 模式四态计数与全量清单逐项一致（ditie +0/-0/~5/=339 等）
  - Fuse：38 组查询分数级对齐（索引 + 分数，1e-9 精度）
  - 性能：demo1（7 sheet / 1631 参数 / 117KB）解析 0.14s < 1s 预算

### 关键实现决策

- CoreXLSX 的 XMLCoder 解码万格级横向 sheet 需 2s+ → worksheet 改用 Foundation XMLParser（17 倍提速）
- CoreXLSX 的严格 SchemaType 对 WPS/SheetJS 非标关系类型（woinfos、sheetMetadata）解码失败 → 关系解析自研
- XML 规范化会把共享字符串中的 \r\n 归一为 \n → 共享字符串从 zip 原始 XML 提取（保留 CRLF）
- golden 基准由旧版真实代码（vite-node 跑 `../vehicle-parameter` 源码）导出，随仓库提交，CI 可全量复验

CI：`.github/workflows/ci.yml`（swift build/test + xcodegen + 免签名 xcodebuild）。

架构蓝图见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，里程碑与验收标准见 [docs/MILESTONES.md](docs/MILESTONES.md)。

## 许可

待定（建议与旧版一致的 MIT）。
