# 架构蓝图

> 版本：v1.0 · 2026-09-26 · 状态：M0 定稿，随实现演进

## 1. 分层架构

```
┌─────────────────────────────────────────────────────┐
│ App Target（SwiftUI 壳）                             │
│  MainShell（导航/侧栏/标签页/菜单栏）                 │
│  Features/：DiffViewer · SmartFiller · Workbench     │
│    · DataPurify · AttributeDedup · AssetLibrary      │
│    · AnnouncementQuery                              │
│  ParameterGrid：NSTableView 封装（NSViewRepresentable）│
├─────────────────────────────────────────────────────┤
│ VehicleKit（Swift Package，纯逻辑域层，无 UI 依赖）    │
│  ExcelParser（CoreXLSX 封装）· MatchingEngine        │
│  Comparator · Deduplicator · Purifier · EnumDict     │
│  VehicleInstance（车型实例 key 语义，与旧版对齐）      │
├─────────────────────────────────────────────────────┤
│ 数据层                                               │
│  GRDB/SQLite（数据池/资产/会话） · 文件 IO            │
│  AssetStore（资产 JSON 兼容读写 v1.0 格式）           │
└─────────────────────────────────────────────────────┘
```

原则：**VehicleKit 不 import SwiftUI/AppKit**，全部可 XCTest 直测；Feature 层用 `@Observable` 模型驱动，参数网格是唯一的重 AppKit 组件。

## 2. 模块映射（旧 TS → 新 Swift）

| 旧模块 | 行数 | 新模块 | 移植策略 |
|---|---|---|---|
| ParameterWorkbench | 4,866 | Features/Workbench + Features/DiffViewer | 最大模块，按 数据池/对比/多车型 拆分移植 |
| SmartFiller | 3,403 | Features/SmartFiller | 匹配引擎逻辑入 VehicleKit，UI 重写 |
| AssetLibrary | 1,131 | Features/AssetLibrary | GRDB + 兼容 JSON 双轨 |
| DiffViewer | 1,036 | Features/DiffViewer | comparator.ts 直译入 VehicleKit |
| DataPurify | 605 | Features/DataPurify | 净化规则直译 |
| AnnouncementQuery | 421 | Features/AnnouncementQuery | bookmarklet 方案保留（openURL + 剪贴板） |
| AttributeDedup | 241 | Features/AttributeDedup | 简单，可提前做（练手 NSTableView） |
| src/utils 逻辑层 | ~3,400 | VehicleKit | **直译重点**：excelParser 672 行、assetManager 408、attributeEnums 378、matchingEngine 210、comparator 等 |

## 3. 数据模型（SQLite schema 草案）

```sql
-- 资产库（同时保留磁盘 JSON 兼容格式，导入导出时转换）
CREATE TABLE assets (
    id INTEGER PRIMARY KEY,
    file_name TEXT NOT NULL,          -- 兼容旧版 xxx.json 文件名
    product_name TEXT NOT NULL,
    created_at TEXT, updated_at TEXT, -- ISO8601，兼容旧版字段
    parameters BLOB                   -- VehicleParameter[] 的 JSON 编码
);
CREATE TABLE asset_tags (
    asset_id INTEGER REFERENCES assets(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    group_id TEXT NOT NULL DEFAULT 'default',
    PRIMARY KEY (asset_id, tag)
);
-- 会话（替代旧版 localStorage persist + session.json）
CREATE TABLE sessions (
    key TEXT PRIMARY KEY,             -- 'current'
    uploaded_files BLOB,              -- SheetData[] JSON
    selected_products BLOB, confirmed BLOB, excluded BLOB, ignored BLOB,
    updated_at TEXT
);
```

**兼容方案**：启动扫描资产目录时读旧 `AssetFileFormat` v1.0 JSON → upsert 进 SQLite；用户在 Finder 放入旧版导出的 JSON 同样可导入。导出时写回同格式 JSON，保证新旧版资产库目录可互用。

## 4. 参数网格组件（ParameterGrid）

- **NSTableView view-based cells** + `NSViewRepresentable` 包装进 SwiftUI
- 行视图复用（`makeView(withIdentifier:)`），万行级滚动满帧
- 单元格编辑器体系（对应旧版 MatchResultTable/DataPurify 的富单元格）：
  - 枚举下拉 → `NSPopUpButton` 或 NSPopover + 列表（带搜索）
  - 自由文本 → 内联 `NSTextField`（IME 组合态系统级保证）
  - 置信度徽标 / 修复入口（RepairableValue）→ NSPopover
  - diff 四态着色：added/removed/modified/unchanged（行背景 + 左侧色条）
- 列宽拖拽、排序、多选、复制导出走 `NSTableView` 原生能力

## 5. 匹配引擎移植（MatchingEngine）

旧版四级匹配语义（`matchingEngine.ts`，Swift 版必须逐条对齐，golden 测试验证）：

| 级别 | 旧版分数 | 说明 |
|---|---|---|
| 精确匹配 | 0 | requirementName == param.name |
| 归一化匹配 | 0.1 | `normalizeName`（去括号/单位/空格）后相等 |
| 别名匹配 | 0.1 / 0.2 | `PARAMETER_ALIASES` 别名词库命中 |
| Fuse 模糊 | ≤ 0.3 | fuse-swift（Fuse.js 官方移植），threshold 0.3 |
| 未匹配 | 1 | |

配套：`PARAMETER_ALIASES` 词库直译为 Swift 字典；`normalizeName` 的正则逐条移植；WeakMap 缓存对应 `NSCache`。

## 6. 测试策略

- **XCTest 移植**：旧版 21 个 vitest 文件（1,082 行）中的核心用例优先移植——utils 8 个（excelParser/matchingEngine/comparator 等）、store 3 个的语义（车型实例 key 规则）
- **golden 对比测试**：用旧仓库 `docs/test_data/` 真实 xlsx（只读！）跑新旧两版，逐字节对比导出 CSV；diff 结果对比四态计数
- VehicleKit 覆盖率目标：匹配引擎与解析器 ≥ 90% 行覆盖

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| NSTableView 富单元格编辑器复杂度（本项目的 20% 硬骨头） | M1 先做只读 diff 表练手；编辑器按 枚举→文本→修复 三步渐进 |
| libxlsxwriter 是 C 库，SPM 互操作 | 封装成独立 XlsxWriterTarget 模块，隔离 unsafe |
| 单人 + agent 开发的 Xcode 工程漂移 | XcodeGen：工程由 project.yml 生成，**禁止手改 xcodeproj** |
| CoreXLSX 只读不写 | 写出依赖 libxlsxwriter，两者边界清晰（解析/导出不共用模型） |
