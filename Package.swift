// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TranscribeMini",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TranscribeMini", targets: ["TranscribeMini"])
    ],
    targets: [
        .executableTarget(
            name: "TranscribeMini"
        ),
        .testTarget(
            name: "TranscribeMiniTests",
            dependencies: ["TranscribeMini"]
        )
    ]
)
