# 里程碑计划

> 版本：v1.0 · 2026-09-26 · 预估按"个人开发者 + AI agent 辅助"口径

## M0 工程脚手架（0.5-1 周）

**范围**：XcodeGen `project.yml`、VehicleKit Swift Package 骨架、CI（`swift test` + `xcodegen generate` 校验）、签名配置占位、GRDB/CoreXLSX/fuse-swift 依赖接入。

**验收**：`xcodegen generate && swift build && swift test` 全绿；空窗口 app 可运行。

## M1 核心域 + 版本对比对齐（3-4 周）

**范围**：excelParser/comparator 直译入 VehicleKit（含 XCTest）；双 Excel 上传 → 表头识别 → diff 四态（added/removed/modified/unchanged）展示；只读 ParameterGrid（diff 着色）；PDFKit 报告导出。

**验收**：
- 旧仓库 `docs/test_data/`（只读）真实文件 diff 四态计数与旧版完全一致
- 527KB 属性池文件解析 < 1s，滚动满帧

## M2 智能填报（3-4 周）

**范围**：MatchingEngine 移植（四级匹配 + 别名词库 + fuse-swift 阈值 0.3）、置信度三色、人工修正（可编辑 ParameterGrid 上线：枚举下拉 → 文本 → 修复入口三步走）、枚举异常检测、车上云模板 xlsx 导出。

**验收**：golden 对比——同一需求文本 + 同一基准库，新旧版匹配结果（参数名/置信度/填报值）逐项一致；导出 xlsx 可被旧版读回。

## M3 多车型数据池 + 资产库（2-3 周）

**范围**：GRDB schema 落地、上传文件池、车型实例 key 语义（excel/asset 来源区分，与旧版 `vehicleInstance.ts` 对齐）、旧资产 JSON 导入兼容、标签系统、批量激活。

**验收**：旧版资产库目录直接挂载可用；导入-导出往返格式无损。

## M4 数据净化 / 属性去重 / 公告查询（2-3 周）

**范围**：净化规则（名称标准化/枚举不匹配检测/字段组过滤）直译；属性去重（属性池文件）；公告查询（openURL + bookmarklet 粘贴导入，与旧版同方案）。

**验收**：PRD V1.0-V4.4 功能清单逐项打勾。

## M5 打磨与分发（1-2 周）

**范围**：菜单栏全快捷键（Cmd+O/S/F…）、Quick Look 预览 xlsx/csv、Shortcuts 自动化、窗口状态记忆、Developer ID 签名 + 公证、Sparkle 2 自动更新、首版 DMG。

**验收**：干净虚拟机上安装运行；Sparkle 升级链路验证；冷启动 < 0.5s、空闲内存 < 40MB 达标。

## 总排期

约 **12-17 周**（3-4 个月），与旧版并行期间旧版只修不加。每个里程碑结束做一次新旧版golden对比回归，防止语义漂移。
