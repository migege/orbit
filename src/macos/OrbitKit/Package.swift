// swift-tools-version: 5.9
import PackageDescription

// OrbitKit — the UI-free core of the Orbit macOS client (Phase 0).
//
// Zero third-party dependencies on purpose: the protocol logic (models, SSE parsing,
// transcript reduction) is pure and unit-tested; only the concrete URLSession transport
// and the Keychain token store touch platform APIs, and those are guarded so the package
// builds and `swift test` runs the logic on Linux CI as well as macOS.
let package = Package(
    name: "OrbitKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OrbitKit", targets: ["OrbitKit"]),
    ],
    targets: [
        .target(name: "OrbitKit"),
        .testTarget(name: "OrbitKitTests", dependencies: ["OrbitKit"]),
    ]
)
