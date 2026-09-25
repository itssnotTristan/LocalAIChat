// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_video_thumbnail_plus",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "flutter-video-thumbnail-plus", targets: ["flutter_video_thumbnail_plus"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_video_thumbnail_plus",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // No PrivacyInfo.xcprivacy or other bundled resources in this plugin.
            ]
        )
    ]
)
