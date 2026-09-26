# vehicle-parameter-swift

> 版本：v0.5.0（M5 分发就绪）· 2026-09-26

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

**M5 打磨与分发完成（2026-09-26），五个里程碑全部交付。性能验收：冷启动 0.27s（目标 <0.5s）· 空闲内存 37.7MB footprint（目标 <40MB）——均达标。**

### M5 交付

- **菜单全快捷键**：功能页切换 Cmd+1~6、打开 Excel Cmd+O、保存资产 Cmd+S、导出报告 ⇧⌘E、查找 ⌘F、检查更新 ⇧⌘U
- **Sparkle 2**：SPM 接入（binary XCFramework），SUFeedURL/SUPublicEDKey 占位于 Info.plist，检查更新菜单就绪；发布前填真实 appcast 与 EdDSA 公钥
- **App Intents**：SwitchFeatureIntent（Shortcuts 可切换六功能页）
- **Quick Look**：应用内 QLPreviewView 浮层预览 xlsx/csv
- **窗口状态记忆**：侧栏选择持久化（UserDefaults）
- **原生侧栏导航**：NavigationSplitView 替代 TabView（仅渲染当前页）
- **DMG 打包**：`scripts/make_dmg.sh`（Release 构建 + hdiutil UDZO，产物 4.1MB）
- **性能测量**：`scripts/measure_launch.sh`（冷启动 + physical footprint 口径——RSS 会把共享框架页虚高算入 60MB+，验收以 footprint 为准）
- **发布前待办（需 Apple Developer 账号）**：Developer ID 签名 → notarytool 公证 → Sparkle appcast（sign_update 签名）→ 替换 Info.plist 占位

### M4 交付

- **VehicleKit 域层**：
  - `Purifier`：名称标准性（字典标准化匹配，空名=非标准）、名称推荐（Fuse 0.6 搜标准字段前3，空名跳过）、枚举不匹配（大小写不敏感——与 SmartFiller 的精确比较不同，旧版两模块语义如此）、异常计数；`FieldGroups`（custom_fields.json 热替换，groups/systemRequired+qualityCheck 双形态）
  - `AttributeDedup`：属性池按「属性名称」去重（首见 required 保留、空名跳过）、CSV 导出（引号转义）、`_去重.csv` 文件名规则
  - `AnnouncementQuery`：工信部查询 URL（percent-encode）、书签脚本逐字符一致、粘贴导入解析（「其它」字段拆分：分号→点号排除小数点→"序号.key:value"/纯文本两级正则；captureRegex 可选组跳位坑已按组数显式分支）
- **UI**：数据净化页（车型选择/分组/搜索/字段组/异常快捷过滤、行内编辑、推荐 popover、覆盖或另存资产）、属性去重页（统计卡+表格+CSV 导出）、公告查询页（三步向导：查询→书签→粘贴导入，预览+设为对比新版本+保存资产）；主窗口六标签页
- **验收测试（72 例全绿）**：净化检测语义、去重 parity（合成属性池样本）、查询 URL、导入拆分（含 3.5L 小数点保护、booklet 逐字符）、坏载荷拒绝

### M3 交付

- **VehicleKit 域层**：
  - `VehicleInstance`：车型实例 key 语义（`source::fileName::productName`）逐条对齐旧版 vehicleInstance.ts——解析/构建/排序（文件名 zh-Hans-CN numeric → asset 在 excel 前）/同名去重编号/选择匹配
  - `AssetStore`：旧版资产目录契约直译——数据文件判定（排除 `_`/`custom_` 前缀）、扫描统计（公告号纯字母数字过滤、车辆型号提取、filled/total）、v1.0 JSON 读写、`_asset_tags.json` 标签映射、`custom_asset_tag_groups.json` 分组配置、重命名同步标签
  - `AssetDatabase`：GRDB SQLite（架构蓝图 §3 schema：assets/asset_tags/sessions，snake_case 列名映射），扫描 upsert 幂等、标签 diff 写库、删除级联、会话持久化
- **UI**：资产库功能页（目录挂载记忆、SwiftUI Table 多选、标签侧栏筛选、批量加标签、批量导出 v1.0、重命名/删除/访达显示、后台同步 SQLite）；主窗口升级三标签页
- **验收测试（61 例全绿）**：实例 key 往返/非法拒绝/同名编号、旧目录挂载（手写旧版格式兼容）、保存-扫描-读回无损（空值不计已填、createdAt 保留、productName 缺省回填与旧版一致）、GRDB 幂等 upsert/标签 diff/级联删除/会话往返

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
