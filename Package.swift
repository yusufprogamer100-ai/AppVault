// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppVault",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "AppVault",
            targets: ["AppVault"]
        ),
    ],
    targets: [
        .target(
            name: "AppVault",
            path: "AppVault",
            exclude: ["ShieldExtension", "Info.plist", "AppVault.entitlements"]
        ),
    ]
)
