// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "OAuthThey",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "OAuthThey",
            targets: ["OAuthThey"]),
    ],
    targets: [
        .target(
            name: "OAuthThey",
            dependencies: []
        ),
        .testTarget(
            name: "OAuthTheyTests",
            dependencies: ["OAuthThey"]),
    ]
)
