// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCJKVInputSwitcher",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacCJKVInputSwitcher", targets: ["MacCJKVInputSwitcher"])],
    targets: [.executableTarget(name: "MacCJKVInputSwitcher")]
)
