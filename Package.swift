// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EVESup",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EVESup", targets: ["EVESup"]),
        .executable(name: "MockEVEClient", targets: ["MockEVEClient"]),
    ],
    targets: [
        // Pure logic shared by the app and the tests: config, cycling, hotkey model, EVE settings files.
        .target(name: "EVESupCore"),
        .executableTarget(
            name: "EVESup",
            dependencies: ["EVESupCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        // A fake "EVE - <name>" window used to test switching without running the game.
        .executableTarget(name: "MockEVEClient"),
        .testTarget(name: "EVESupCoreTests", dependencies: ["EVESupCore"]),
    ]
)
