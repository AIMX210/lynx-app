// swift-tools-version:5.9
import PackageDescription

// Lynx — 原生 macOS SSH 服务器管理 / 监控 / 终端 / 文件 / Docker 工具
//
// 架构：
//   LynxCore  纯 Foundation 逻辑层（模型、远端脚本、解析器、exec 运行器、命令构造），
//             跨平台，可在 Linux 上单独构建与单元测试。
//   Lynx      macOS 应用层（SwiftUI/AppKit + SwiftTerm 终端 + Keychain + 系统集成）。
//
// SSH 传输复用系统 OpenSSH：每台服务器一条 ControlMaster 长连接，
// 终端 / 监控 / 文件 / Docker / 端口转发全部走同一条连接的复用通道，资源占用极低。

var packageDependencies: [Package.Dependency] = []
var appTargets: [Target] = []

#if os(macOS)
// 以 revision 锁定 v1.9.0 tag 同一份代码（commit 8840e359）。
// 不用 exact 稳定版：SwiftTerm 1.9.0 自身以 revision 锁 swift-subprocess，
// SPM 禁止「稳定版根依赖 → 不稳定版传递依赖」边；revision 锁法合规且完全确定。
packageDependencies.append(
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "8840e3596739adfe9599c0e7fff89f4fa88bedcf")
)
appTargets.append(
    .executableTarget(
        name: "Lynx",
        dependencies: [
            "LynxCore",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
        ],
        path: "Sources/Lynx"
    )
)
#endif

let package = Package(
    name: "Lynx",
    platforms: [.macOS(.v14)],
    dependencies: packageDependencies,
    targets: [
        .target(name: "LynxCore", path: "Sources/LynxCore"),
        .testTarget(name: "LynxCoreTests", dependencies: ["LynxCore"], path: "Tests/LynxCoreTests"),
    ] + appTargets,
    swiftLanguageVersions: [.v5]
)