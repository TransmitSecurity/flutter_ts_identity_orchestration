# Flutter TS Identity Orchestration Plugin

Production-ready Flutter plugin for Transmit Security Identity Orchestration.

## Build Info
- Built: Mon Jan 12 12:36:36 EST 2026
- Commit: 13d14bb
- Flutter: Flutter 3.38.3 • channel stable • https://github.com/flutter/flutter.git

## Installation

Add to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  flutter_ts_identity_orchestration:
    git:
      url: https://github.com/TransmitSecurity/flutter_ts_identity_orchestration.git
      ref: v0.0.1  # Use the latest version tag
```

Then run:
```bash
flutter pub get
```

## Usage

```dart
import 'package:flutter_ts_identity_orchestration/flutter_ts_identity_orchestration.dart';

final orchestration = FlutterTsIdentityOrchestration();

// Initialize SDK with configuration file
await orchestration.initializeSDK(configurationFile: 'TransmitSecurity.plist');

// Or initialize with parameters
await orchestration.initialize(
  clientId: 'your-client-id',
  options: {
    'serverPath': 'https://api.transmitsecurity.io',
  },
);

// Start a journey
await orchestration.startJourney(journeyId: 'your-journey-id');

// Listen to journey responses
orchestration.journeyResponseStream.listen((response) {
  print('Journey response: $response');
});
```
