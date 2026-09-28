import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_ts_identity_orchestration_method_channel.dart';
import 'modular_idv_hook.dart';

abstract class FlutterTsIdentityOrchestrationPlatform
    extends PlatformInterface {
  FlutterTsIdentityOrchestrationPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterTsIdentityOrchestrationPlatform _instance =
      MethodChannelFlutterTsIdentityOrchestration();
  static FlutterTsIdentityOrchestrationPlatform get instance => _instance;

  static set instance(FlutterTsIdentityOrchestrationPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> initializeSDK({String? configurationFile}) {
    throw UnimplementedError('initializeSDK() has not been implemented.');
  }

  Future<void> initialize({
    required String clientId,
    required Map<String, dynamic> options,
  }) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<void> startJourney({
    required String journeyId,
    Map<String, dynamic>? options,
  }) {
    throw UnimplementedError('startJourney() has not been implemented.');
  }

  Future<bool> submitClientResponse({
    required String responseId,
    Map<String, dynamic>? data,
  }) {
    throw UnimplementedError(
      'submitClientResponse() has not been implemented.',
    );
  }

  Future<String> generateDebugPin() {
    throw UnimplementedError('generateDebugPin() has not been implemented.');
  }

  Future<void> startMobileApproveJourney({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> startJourneyOptions,
  }) {
    throw UnimplementedError(
      'startMobileApproveJourney() has not been implemented.',
    );
  }

  Future<bool> setLoggingEnabled(bool enabled) {
    throw UnimplementedError('setLoggingEnabled() has not been implemented.');
  }

  Future<void> setPushToken(String token) {
    throw UnimplementedError('setPushToken() has not been implemented.');
  }

  Stream<Map<String, dynamic>> get journeyResponseStream {
    throw UnimplementedError('journeyResponseStream has not been implemented.');
  }

  Future<bool> setModularIdvHooks({
    bool onBefore = false,
    bool onAfter = false,
  }) {
    throw UnimplementedError('setModularIdvHooks() has not been implemented.');
  }

  Future<bool> resumeModularIdvStep({
    required String hookId,
    String? responseId,
    Map<String, dynamic>? data,
  }) {
    throw UnimplementedError(
      'resumeModularIdvStep() has not been implemented.',
    );
  }

  Stream<ModularIdvHookEvent> get modularIdvHookStream {
    throw UnimplementedError('modularIdvHookStream has not been implemented.');
  }
}
