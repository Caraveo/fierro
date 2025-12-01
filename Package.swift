// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Fierro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Fierro",
            targets: ["Fierro"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Fierro",
            dependencies: [],
            exclude: ["FerrofluidShader.metal"],
            resources: [
                .process("start.wav"),
                .process("touch.wav")
            ]
        )
    ]
)

