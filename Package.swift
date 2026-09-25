// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpusLite",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "OpusLite",
            path: "Sources/OpusLite",
            swiftSettings: [.unsafeFlags(["-Osize"])]
        )
    ]
)
