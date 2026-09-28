import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_ts_identity_orchestration_platform_interface.dart';
import 'modular_idv_hook.dart';

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

  /// The single broadcast stream backing both [journeyResponseStream] and
  /// [modularIdvHookStream].
  ///
  /// Created once, deliberately. `receiveBroadcastStream()` triggers a fresh `onListen` on the
  /// native side per call, and both platform plugins hold **one** event sink — so calling it twice
  /// would have the second listener overwrite the first's sink and silently kill it. Sharing one
  /// stream and filtering per consumer keeps a single native subscription.
  Stream<Map<String, dynamic>>? _events;

  Stream<Map<String, dynamic>> get _eventStream {
    return _events ??= eventChannel.receiveBroadcastStream().map(
      (event) => Map<String, dynamic>.from(event as Map),
    );
  }

  @override
  Stream<Map<String, dynamic>> get journeyResponseStream {
    // Hook events are excluded rather than passed through: an app that enables hooks would
    // otherwise start seeing events on its journey stream that its existing handling cannot
    // interpret. They are available, typed, on [modularIdvHookStream].
    return _eventStream.where(
      (event) => !ModularIdvHookEvent.isHookEvent(event),
    );
  }

  @override
  Stream<ModularIdvHookEvent> get modularIdvHookStream {
    return _eventStream
        .where(ModularIdvHookEvent.isHookEvent)
        .map(ModularIdvHookEvent.fromEvent)
        .where((event) => event != null)
        .cast<ModularIdvHookEvent>();
  }

  @override
  Future<bool> setModularIdvHooks({
    bool onBefore = false,
    bool onAfter = false,
  }) async {
    final result = await methodChannel.invokeMethod<bool>(
      'setModularIdvHooks',
      <String, dynamic>{'onBefore': onBefore, 'onAfter': onAfter},
    );
    return result ?? false;
  }

  @override
  Future<bool> resumeModularIdvStep({
    required String hookId,
    String? responseId,
    Map<String, dynamic>? data,
  }) async {
    final result = await methodChannel.invokeMethod<bool>(
      'resumeModularIdvStep',
      <String, dynamic>{
        'hookId': hookId,
        'responseId': responseId,
        'data': data,
      },
    );
    return result ?? false;
  }
}
