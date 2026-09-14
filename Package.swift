// swift-tools-version: 6.0
import PackageDescription

// FlyKit is the domain layer: what the fly is doing and how spikes become behaviour. It has
// no platform dependencies and no knowledge of the C engine — which is what lets the same
// rules be tested in milliseconds instead of round-tripping through a simulator.
// Clean Architecture: entities point inward. The connectome itself lives in Rust
// (superduper-dsp/connectome-core) and reaches the app as FlyBrain.xcframework.
let package = Package(
    name: "FlyKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "FlyKit", targets: ["FlyKit"]),
    ],
    targets: [
        .target(name: "FlyKit"),
        .testTarget(name: "FlyKitTests", dependencies: ["FlyKit"]),
    ]
)
