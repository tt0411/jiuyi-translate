// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SelectionTranslate",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "SelectionTranslate")],
    swiftLanguageModes: [.v5]
)
