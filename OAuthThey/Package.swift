// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "OAuthThey",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
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
