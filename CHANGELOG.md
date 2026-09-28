# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.5] - 2026-09-02

Updated to IDO Android native SDK **1.0.34** and IDO iOS native SDK **1.2.3**, and adds
Modular IDV support on both platforms.

This plugin version pins the IDO native SDKs itself, so IDO versions are not configurable per
integration — to move to a newer IDO, move to a newer plugin version. **IDV is the exception:** it
is not bundled, and you add it yourself only if you want Modular IDV, at **1.3.5 or higher**. See
*Bundled native SDK versions* and *Modular IDV → Adding the IDV native SDK* in `UserGuide.md`.

### Added
- **Risk data collection** (`collectRiskData`): opt-in device data collection for fraud
  detection on journey startup. Available on both platforms.
  - In code via `initialize(options: {'collectRiskData': true})`.
  - Via platform configuration for `initializeSDK()`: a top-level `collectRiskData`
    boolean in `TransmitSecurity.plist` (iOS) or a
    `transmit_security_collect_risk_data` bool resource (Android).
  - Read only at initialization; changing it later has no effect.
- **`drsSessionToken` start-journey option** to associate a journey with a DRS session,
  accepted by both `startJourney` and `startMobileApproveJourney`. Now implemented on
  **both platforms** — Android support landed in native SDK 1.0.33.
- **`code` field on journey responses**, carrying the backend token exchange code on
  successful journey completion. **iOS only** at these native versions — the key is
  absent from the response map on Android rather than present-and-null.
- **Modular IDV (document/selfie acquisition) — now on both platforms.** When a journey
  reaches a document or selfie acquisition step, the native SDK launches its own capture
  UI and continues the journey once the user finishes. iOS support arrives with native
  SDK 1.2.3; Android has had it since 1.0.34. By default no plugin API is involved —
  the plugin registers the SDK's UI handler internally and the flow is driven
  natively. See the new hooks below to interject around a step.
  - Requires **Camera** permission. Declare `NSCameraUsageDescription` on iOS and request
    `android.permission.CAMERA` on Android; see the example app for both patterns.
  - **You add the IDV native SDK yourself** — the plugin does not bundle it, so Modular
    IDV is opt-in and apps that do not use it ship neither IDV nor AccountProtection.
    **`IdentityVerification` 1.3.5 or higher is mandatory**; on iOS an older version
    crashes the app on launch. See *Modular IDV → Adding the IDV native SDK* in
    `UserGuide.md` for per-platform instructions and the full rationale.
- **Modular IDV hooks** — `setModularIdvHooks()`, `modularIdvHookStream`,
  `proceedModularIdvStep()` and `submitModularIdvStep()`. Lets an app show its own
  screens before or after a document/selfie acquisition step, or branch the journey
  instead of running the SDK's capture flow. Available on **both platforms**, and
  exposes the native SDKs' `onBefore` / `onAfter` hooks, which had no Dart equivalent
  before.
  - **Off by default, and leaving them off changes nothing.** Existing integrations are
    unaffected: acquisition still proceeds automatically with no Dart involvement.
  - **An enabled hook pauses the journey until you resume it**, with no timeout and no
    error. Subscribe to `modularIdvHookStream` before enabling, and make sure every
    branch of your handler ends in exactly one resume call. See *Modular IDV → Hooks*
    in `UserGuide.md`.
  - Hook events are delivered only on `modularIdvHookStream`, never on
    `journeyResponseStream`, so enabling them cannot introduce unrecognized events into
    existing journey handling.
  - The IDV session token is deliberately not exposed to Dart — it is a credential only
    the native SDK can act on.
- **IDV recommendation journey step** (`transmit_platform_idv_recommendation`). Follows the
  acquisition steps while the server computes the recommendation asynchronously. Resubmit
  an empty `clientInput` response each time the step is delivered; the journey advances on
  its own once the recommendation resolves. Do not add client-side backoff — pacing is
  handled by the SDK and server. The example app shows the loop.

### Fixed
- **Backend token exchange code no longer dropped (iOS).** The native SDK previously
  parsed the code out of the server response and never surfaced it, so it never reached
  the app. It is now exposed as `code` on the journey response.
- **`drsSessionToken` is now trimmed on both platforms.** Android previously forwarded the value
  verbatim while iOS trimmed it, so `" abc "` produced a different header on each platform and the
  padded one would not match server-side. Both now trim, and a whitespace-only value is treated as
  omitted on both.
- **Modular IDV errors now carry a usable `errorCode` on iOS.** They previously arrived as
  an opaque internal-error description, so a camera-permission refusal was indistinguishable
  from an internal IDV failure. They now use the same string codes Android already emits —
  `idv_camera_permission_required`, `idv_sdk_disabled`, `idv_session_not_valid`,
  `idv_initialization_error`, `idv_not_initialized`, `idv_canceled`, `idv_internal_error`,
  `idv_not_available`. Non-IDV errors are unchanged.
- **A failed `startJourney`, `startMobileApproveJourney` or `submitClientResponse` now reports the
  native error code.** These calls previously threw a `PlatformException` whose `details` was
  `null`, so the only identifying information was the operation name in `code` — the same value for
  every possible cause. An app could not tell a missing IDV SDK from a network failure without
  substring-matching the message. `details` now carries `errorCode` and `errorMessage`; see
  *Error codes* in `UserGuide.md`. Additive: `details` was previously `null` on these paths.

### Changed
- **⚠️ Breaking (Android only): journey-response `errorData.errorCode` is now the documented
  snake_case value.** It previously emitted the native Kotlin enum's constant name, so an app saw
  `IdvNotAvailable` where `UserGuide.md` documented `idv_not_available` — and where iOS already
  emitted `idv_not_available`. Android now emits the SDK's own wire value, matching both the
  documentation and iOS.
  - **Affects every code on this path, not just the IDV ones** — e.g. `NetworkError` →
    `network_error`, `ServerError` → `server_error`.
  - **Action required** if your Android code matches on the PascalCase spelling. Code written
    against the documented values, or shared across both platforms, already works.
  - iOS is unaffected; it was already correct.
- **PIN code transaction signing** journey step is now recognized as a dedicated action
  type on **both platforms** (Android support landed in native SDK 1.0.33). The raw
  server step id was already delivered unchanged on both platforms before this, so
  there is no behavior change for existing integrations.
- **Android apps now receive Play Services transitively.** The shared core SDK adds
  `com.google.android.gms:play-services-location` 20.0.0, plus `play-services-base`
  18.0.1, `play-services-basement` 18.0.0 and `play-services-tasks` 18.0.1. Check for a
  version conflict if your app already depends on Play Services.
- **Consumer ProGuard/R8 rules extended** to keep the shared core device-data and
  geolocation classes, which are serialized reflectively when `collectRiskData` is
  enabled, plus Gson `TypeToken` generic signatures used when parsing journey responses.
  No configuration is required in your app.
- **`com.ts.sdk:core` bumped to 1.1.1** on Android, transitively via IDO. Check for a
  version conflict if your app already depends on core directly.
- **The IDV native SDK is no longer declared by the plugin, on either platform.** Modular
  IDV is now opt-in: you add `com.ts.sdk:identityverification` (Android) or
  `identityVerification-ios-sdk` (iOS) to your own app, and apps that do not want Modular
  IDV ship neither IDV nor its transitive AccountProtection. The plugin's own code
  references no IDV symbols — IDV is needed only to satisfy the IDO SDK's runtime probe.
  - **`IdentityVerification` 1.3.5 or higher is mandatory.** Not adding IDV at all is
    safe and yields `idv_not_available`; adding an **older** version is not. On iOS it
    causes a launch crash for every user, because the IDO framework references IDV
    symbols as hard undefined while the class-presence check still passes. Android
    degrades gracefully via reflection, but do not rely on that.
  - **iOS is SPM-only** for this — the IDO and IDV iOS SDKs are not on CocoaPods.
  - See *Modular IDV → Adding the IDV native SDK* in `UserGuide.md`.
- **`transmit_platform_selfie_acquisition` is now dual-purpose.** It carries both the
  existing face-authentication step and the new Modular IDV selfie acquisition. Existing
  face-authentication journeys are unaffected; a journey configured for Modular IDV routes
  the same step id to the native capture UI.

### Known issues
- **iOS: a Modular IDV step with the IDV SDK absent hangs the journey.** The native SDK logs
  `Failed to initialize modular IDV controller` and `Failed to start IDV selfie acquisition`
  (`IdoError` 1008, "The SDK is not available") and swallows both, so no error reaches the app and
  the journey neither advances nor terminates. Android rejects the journey with
  `idv_not_available` as documented. If you ship iOS without IDV, apply your own timeout or ensure
  your journeys do not configure Modular IDV for that build. See *Modular IDV* in `UserGuide.md`.

### Notes
- Geolocation within risk data is opt-in and degrades gracefully: the SDK declares no
  location permission. If your app declares and is granted `ACCESS_FINE_LOCATION` or
  `ACCESS_COARSE_LOCATION`, location is included; otherwise collection proceeds without
  it. You do not need to request a location permission for risk data to work.
- If your app enables R8/ProGuard shrinking, no action is needed for the Play Core
  warning that `identityverification` can otherwise cause R8 to raise (it references
  Flutter's unused deferred-components code path) — the plugin now ships a consumer
  rule that suppresses it automatically.

## [0.0.1] - 2026-01-05

### Added
- **Initial release** of Flutter TS Identity Orchestration plugin
- **Core SDK Integration**:
  - SDK initialization with client ID and configuration options
  - Configuration file support for SDK setup
- **Authentication Journey Management**:
  - Start identity orchestration journeys with custom options
  - Submit client responses to journey steps
  - Real-time journey event streaming via `journeyResponseStream`
- **Mobile Approve Support**:
  - Start mobile approve journeys with payload and options
  - Handle mobile approval workflows
- **Platform Support**:
  - iOS support (minimum iOS 13.0)
  - Android support (minimum API level 21)
- **Developer Tools**:
  - Debug pin generation for development and testing
  - Logging control with `setLoggingEnabled()`
  - Push token management with `setPushToken()`
- **Native SDK Integration**:
  - WebAuthn SDK integration for iOS and Android
  - Transmit Security Identity Orchestration platform connectivity
- **Plugin Architecture**:
  - Platform interface for cross-platform consistency
  - Method channel implementation for native communication
  - Stream-based event handling for real-time updates
- **Documentation**:
  - Comprehensive User Guide with setup instructions
  - Platform-specific configuration examples
  - API reference and usage examples
  - Troubleshooting and best practices guide

### Technical Requirements
- Flutter 3.3.0 or higher
- Dart SDK 2.17.0 or higher
- iOS 13.0+ with Xcode 12+
- Android API level 21+ (Android 5.0)

### Dependencies
- `plugin_platform_interface: ^2.0.2`
- Transmit Security native SDKs (automatically managed)
