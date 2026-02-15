// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TranscribeMini",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TranscribeMini", targets: ["TranscribeMini"]),
        .executable(name: "TranscribeBench", targets: ["TranscribeBench"])
    ],
    targets: [
        .executableTarget(
            name: "TranscribeMini"
        ),
        .executableTarget(
            name: "TranscribeBench"
        ),
        .testTarget(
            name: "TranscribeMiniTests",
            dependencies: ["TranscribeMini"]
        )
    ]
)
