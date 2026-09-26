// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "vehicle-parameter-swift",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VehicleKit", targets: ["VehicleKit"])
    ],
    dependencies: [
        // Excel 只读解析；写出走 libxlsxwriter（App 侧独立模块，M2 接入）
        .package(url: "https://github.com/CoreOffice/CoreXLSX", from: "0.14.2"),
        // 自行读取 zip 条目（rels 等）：CoreXLSX 对非标关系类型（WPS/SheetJS 写出的
        // woinfos、sheetMetadata）会解码失败，关系解析必须绕开其严格 SchemaType
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
        // 数据池/资产库/会话持久化（SQLite）。GRDB 纯 Swift 无 UI 依赖，放入 VehicleKit
        // 保证数据层全量 XCTest 直测（架构蓝图 §3 schema）
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        // 模糊匹配不引 fuse-swift：fuse.js@7.1.0 已逐行为移植进 VehicleKit（FuseSearch.swift），
        // fuse-swift 与 fuse.js 打分语义存在偏差，会破坏 golden 四态计数契约
    ],
    targets: [
        // libxlsxwriter C 互操作隔离层（AGENTS.md：C 接口封装集中管理，不散写）。
        // 依赖 Homebrew libxlsxwriter（brew install libxlsxwriter），CI 同步安装。
        .systemLibrary(
            name: "XlsxWriterShim",
            path: "VehicleKit/Support/XlsxWriterShim",
            pkgConfig: "xlsxwriter"
        ),
        .target(
            name: "VehicleKit",
            dependencies: [
                .product(name: "CoreXLSX", package: "CoreXLSX"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "GRDB", package: "GRDB.swift"),
                "XlsxWriterShim",
            ],
            path: "VehicleKit/Sources",
            resources: [
                // 属性枚举值字典（与旧版 src/assets/attribute_values.txt 同源）
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "VehicleKitTests",
            dependencies: ["VehicleKit"],
            path: "VehicleKit/Tests",
            resources: [
                // golden 基准：旧版真实代码跑出的解析/对比快照 + 真实/合成 xlsx 样本
                .copy("Golden")
            ]
        ),
    ]
)
