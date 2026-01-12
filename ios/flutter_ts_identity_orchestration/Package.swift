// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_ts_identity_orchestration",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-ts-identity-orchestration", targets: ["flutter_ts_identity_orchestration"])
    ],
    dependencies: [
        .package(url: "https://github.com/TransmitSecurity/identityOrchestration-ios-sdk", exact: "1.1.20")
    ],
    targets: [
        .target(
            name: "flutter_ts_identity_orchestration",
            dependencies: [
                .product(name: "IdentityOrchestration", package: "identityOrchestration-ios-sdk")
            ],
            resources: [
    
            ]
        )
    ]
)
