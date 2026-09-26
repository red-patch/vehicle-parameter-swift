# AGENTS.md — vehicle-parameter-swift

> 本文件是所有 AI coding agent 的项目入口。改代码前必读。

## 项目简介

车辆整车参数配置与管理工具的 macOS 原生重写版（Swift 6 + SwiftUI + NSTableView）。
旧版 Tauri 应用在 `../vehicle-parameter`（同目录兄弟仓库），继续服务 Windows 用户；
本项目功能以旧版 `docs/PRD.md` 为对齐基准，资产库 JSON 格式保持互通。

架构蓝图见 `docs/ARCHITECTURE.md`，里程碑与验收标准见 `docs/MILESTONES.md`。

## 验证命令（改完代码必须跑）

```bash
xcodegen generate   # 重新生成 Xcode 工程（改了文件结构/依赖后必须跑）
swift build         # VehicleKit 编译
swift test          # VehicleKit 单元测试
```

UI 侧改动至少跑 `xcodegen generate` 后 Xcode 构建通过；逻辑改动三条全跑。

## 目录地图（随 M0 建立）

| 路径 | 说明 |
|---|---|
| `VehicleKit/` | 纯逻辑域层（解析/匹配/对比/去重/净化），无 UI 依赖，可全量 XCTest |
| `App/` | SwiftUI 壳 + Feature 模块 |
| `App/ParameterGrid/` | NSTableView 封装（核心可编辑表格组件） |
| `docs/` | 架构蓝图、里程碑 |
| `project.yml` | XcodeGen 工程定义（唯一事实来源） |

## 边界与约定

- **旧仓库 `../vehicle-parameter/docs/` 下的真实车辆数据（.xlsx/.csv）只读**，用于 golden 对比测试，不要修改
- 资产 JSON 兼容格式（version 1.0：productName/createdAt/updatedAt/parameters）是新旧版互通契约，字段变更需双向兼容
- 不要提交签名私钥、公证密码、`.env`、任何凭证文件
- 匹配引擎的分数语义（exact 0 / normalized 0.1 / alias 0.1-0.2 / fuzzy ≤0.3）是 golden 测试的契约，改动必须同步旧版或说明理由

## 已知坑

- **xcodeproj 由 XcodeGen 生成，禁止手改**——改工程结构只改 `project.yml` 然后重新 generate
- libxlsxwriter 是 C 库，接口封装集中在独立模块，不要在 Swift 代码里散写 C 互操作
- NSTableView 单元格编辑器在 IME 组合态下的行为要在真机验证，不要只信单元测试
