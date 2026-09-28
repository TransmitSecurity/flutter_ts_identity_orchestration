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
        // IdentityVerification is deliberately NOT declared here. Modular IDV is opt-in: an app
        // that wants it links `identityVerification-ios-sdk` in its own Xcode project, so apps
        // that do not want it ship neither IDV nor its transitive AccountProtection. Integrator
        // instructions live in UserGuide.md under "Modular IDV".
        //
        // This plugin's own sources reference ZERO IdentityVerification symbols — every Modular
        // IDV type used here (ITSUIHandler, TSIDVStepHandler, TSIDVAcquisitionContext,
        // TSAcquisitionStepData) belongs to IdentityOrchestration. IDV is needed only to satisfy
        // IdentityOrchestration's own runtime probe, so dropping it costs no compilation.
        //
        // ⚠️ IdentityVerification 1.3.5 or higher is a HARD requirement on iOS, not a
        // recommendation. IdentityOrchestration weak-links the framework but references its
        // symbols as `(undefined) external`, NOT weak-imported:
        //   - IDV absent          -> symbols bind to 0, objc_getClass returns nil, the SDK
        //                            reports idv_not_available, journey rejected. SAFE.
        //   - IDV present but old -> the framework loads and objc_getClass SUCCEEDS, because the
        //                            TSIdentityVerification class predates Modular IDV. The guard
        //                            passes, then the missing startDocumentAcquisition /
        //                            startSelfieAcquisition symbol is a dyld symbol-not-found and
        //                            the app CRASHES — for every user, whether or not they ever
        //                            reach a Modular IDV step.
        // Android tolerates an old IDV because its adapter uses reflection; iOS does not.
        .package(url: "https://github.com/TransmitSecurity/identityOrchestration-ios-sdk", exact: "1.2.3")
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
