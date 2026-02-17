import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_ts_identity_orchestration_platform_interface.dart';

class MethodChannelFlutterTsIdentityOrchestration
    extends FlutterTsIdentityOrchestrationPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel(
    'flutter_ts_identity_orchestration',
  );

  @visibleForTesting
  final eventChannel = const EventChannel(
    'flutter_ts_identity_orchestration_events',
  );

  @override
  Future<void> initializeSDK({String? configurationFile}) async {
    final arguments = <String, dynamic>{'configurationFile': configurationFile};
    await methodChannel.invokeMethod<void>('initializeSDK', arguments);
  }

  @override
  Future<void> initialize({
    required String clientId,
    required Map<String, dynamic> options,
  }) async {
    final arguments = <String, dynamic>{
      'clientId': clientId,
      'options': options,
    };
    await methodChannel.invokeMethod<void>('initialize', arguments);
  }

  @override
  Future<void> startJourney({
    required String journeyId,
    Map<String, dynamic>? options,
  }) async {
    final arguments = <String, dynamic>{
      'journeyId': journeyId,
      'options': options,
    };
    await methodChannel.invokeMethod<void>('startJourney', arguments);
  }

  @override
  Future<bool> submitClientResponse({
    required String responseId,
    Map<String, dynamic>? data,
  }) async {
    final arguments = <String, dynamic>{'responseId': responseId, 'data': data};
    final result = await methodChannel.invokeMethod<bool>(
      'submitClientResponse',
      arguments,
    );
    return result ?? false;
  }

  @override
  Future<String> generateDebugPin() async {
    final result = await methodChannel.invokeMethod<String>('generateDebugPin');
    return result ?? '';
  }

  @override
  Future<void> startMobileApproveJourney({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> startJourneyOptions,
  }) async {
    final arguments = <String, dynamic>{
      'payload': payload,
      'startJourneyOptions': startJourneyOptions,
    };
    await methodChannel.invokeMethod<void>(
      'startMobileApproveJourney',
      arguments,
    );
  }

  @override
  Future<bool> setLoggingEnabled(bool enabled) async {
    final result = await methodChannel.invokeMethod<bool>('setLoggingEnabled', {
      'enabled': enabled,
    });
    return result ?? false;
  }

  @override
  Future<void> setPushToken(String token) async {
    await methodChannel.invokeMethod<void>('setPushToken', {'token': token});
  }

  @override
  Stream<Map<String, dynamic>> get journeyResponseStream {
    return eventChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event),
    );
  }
}
