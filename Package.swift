// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "OAuthThey",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "OAuthThey",
            targets: ["OAuthThey"]),
    ],
    targets: [
        .target(
            name: "OAuthThey",
            dependencies: []),
        .testTarget(
            name: "OAuthTheyTests",
            dependencies: ["OAuthThey"]),
    ]
)
