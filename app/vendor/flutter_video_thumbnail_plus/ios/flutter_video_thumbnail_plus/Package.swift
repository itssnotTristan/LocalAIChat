// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_video_thumbnail_plus",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-video-thumbnail-plus", targets: ["flutter_video_thumbnail_plus"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Mirrors the CocoaPods `libwebp` dependency used for WebP encoding.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.3.2")
    ],
    targets: [
        .target(
            name: "flutter_video_thumbnail_plus",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "libwebp", package: "libwebp-Xcode")
            ],
            resources: [
                // No PrivacyInfo.xcprivacy or other bundled resources in this plugin.
            ],
            cSettings: [
                .headerSearchPath("include/flutter_video_thumbnail_plus")
            ]
        )
    ]
)
