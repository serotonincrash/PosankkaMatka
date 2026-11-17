// swift-tools-version: 6.0

import PackageDescription

/// Platform-neutral app logic (no SwiftUI, MapKit or CoreLocation), shared by
/// the iOS app and the Android build.
let package = Package(
    name: "PosankkaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PosankkaCore", targets: ["PosankkaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/serotonincrash/FoliBusAPI", from: "2.3.0"),
    ],
    targets: [
        .target(
            name: "PosankkaCore",
            dependencies: [.product(name: "FoliBusAPI", package: "FoliBusAPI")]
        ),
        .testTarget(name: "PosankkaCoreTests", dependencies: ["PosankkaCore"]),
    ]
)
