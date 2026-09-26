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
        // 模糊匹配不引 fuse-swift：fuse.js@7.1.0 已逐行为移植进 VehicleKit（FuseSearch.swift），
        // fuse-swift 与 fuse.js 打分语义存在偏差，会破坏 golden 四态计数契约
        // GRDB（数据池/资产库 SQLite）属 App 侧数据层，经 project.yml 接入，不进 VehicleKit
    ],
    targets: [
        .target(
            name: "VehicleKit",
            dependencies: [
                .product(name: "CoreXLSX", package: "CoreXLSX"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "VehicleKit/Sources"
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
