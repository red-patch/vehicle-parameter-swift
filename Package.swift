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
        // Fuse.js 官方 Swift 移植，阈值语义与旧版 matchingEngine.ts 对齐
        .package(url: "https://github.com/krisk/fuse-swift", from: "1.4.0"),
        // GRDB（数据池/资产库 SQLite）属 App 侧数据层，经 project.yml 接入，不进 VehicleKit
    ],
    targets: [
        .target(
            name: "VehicleKit",
            dependencies: [
                .product(name: "CoreXLSX", package: "CoreXLSX"),
                .product(name: "Fuse", package: "fuse-swift"),
            ],
            path: "VehicleKit/Sources"
        ),
        .testTarget(
            name: "VehicleKitTests",
            dependencies: ["VehicleKit"],
            path: "VehicleKit/Tests"
        ),
    ]
)
