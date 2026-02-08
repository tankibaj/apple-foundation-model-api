// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AFMAPI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "afm-api-server", targets: ["AFMAPI"])
    ],
    targets: [
        .executableTarget(
            name: "AFMAPI",
            path: "Sources/AFMAPI"
        )
    ]
)
