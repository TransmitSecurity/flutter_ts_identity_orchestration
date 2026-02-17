# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
