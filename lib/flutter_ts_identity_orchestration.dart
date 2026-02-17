import 'flutter_ts_identity_orchestration_platform_interface.dart';

class FlutterTsIdentityOrchestration {
  Future<void> initializeSDK({String? configurationFile}) {
    return FlutterTsIdentityOrchestrationPlatform.instance.initializeSDK(
      configurationFile: configurationFile,
    );
  }

  Future<void> initialize({
    required String clientId,
    required Map<String, dynamic> options,
  }) {
    return FlutterTsIdentityOrchestrationPlatform.instance.initialize(
      clientId: clientId,
      options: options,
    );
  }

  Future<void> startJourney({
    required String journeyId,
    Map<String, dynamic>? options,
  }) {
    return FlutterTsIdentityOrchestrationPlatform.instance.startJourney(
      journeyId: journeyId,
      options: options,
    );
  }

  Future<bool> submitClientResponse({
    required String responseId,
    Map<String, dynamic>? data,
  }) {
    return FlutterTsIdentityOrchestrationPlatform.instance.submitClientResponse(
      responseId: responseId,
      data: data,
    );
  }

  Future<String> generateDebugPin() {
    return FlutterTsIdentityOrchestrationPlatform.instance.generateDebugPin();
  }

  Future<void> startMobileApproveJourney({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> startJourneyOptions,
  }) {
    return FlutterTsIdentityOrchestrationPlatform.instance
        .startMobileApproveJourney(
          payload: payload,
          startJourneyOptions: startJourneyOptions,
        );
  }

  Future<bool> setLoggingEnabled(bool enabled) {
    return FlutterTsIdentityOrchestrationPlatform.instance.setLoggingEnabled(
      enabled,
    );
  }

  Future<void> setPushToken(String token) {
    return FlutterTsIdentityOrchestrationPlatform.instance.setPushToken(token);
  }

  Stream<Map<String, dynamic>> get journeyResponseStream {
    return FlutterTsIdentityOrchestrationPlatform
        .instance
        .journeyResponseStream;
  }
}
