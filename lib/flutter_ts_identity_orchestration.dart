import 'flutter_ts_identity_orchestration_platform_interface.dart';
import 'modular_idv_hook.dart';

export 'modular_idv_hook.dart'
    show
        ModularIdvAcquisitionType,
        ModularIdvHookEvent,
        ModularIdvHookPoint,
        ModularIdvResponseOption;

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

  /// Enables or disables the Modular IDV hooks, which let the app interject around document and
  /// selfie acquisition.
  ///
  /// **Both are off by default, and leaving them off preserves today's behaviour exactly**: the
  /// native SDK runs capture and advances the journey on its own. Enabling a hook makes the SDK
  /// stop and wait — every event on [modularIdvHookStream] must be resumed with
  /// [proceedModularIdvStep] or [submitModularIdvStep], or the journey stalls at that step with no
  /// timeout and no error. Enable a hook only if you are listening.
  ///
  /// Takes effect from the next acquisition step. A step already suspended in a hook keeps the
  /// behaviour it started with, and disabling does not resume it.
  Future<bool> setModularIdvHooks({
    bool onBefore = false,
    bool onAfter = false,
  }) {
    return FlutterTsIdentityOrchestrationPlatform.instance.setModularIdvHooks(
      onBefore: onBefore,
      onAfter: onAfter,
    );
  }

  /// Acquisition steps suspended in a hook, each awaiting a resume call.
  ///
  /// Emits nothing unless a hook is enabled via [setModularIdvHooks]. Events whose payload cannot
  /// be understood are dropped rather than thrown, so a single malformed event cannot tear down the
  /// subscription and strand every later hook.
  Stream<ModularIdvHookEvent> get modularIdvHookStream {
    return FlutterTsIdentityOrchestrationPlatform.instance.modularIdvHookStream;
  }

  /// Continues a suspended acquisition step along the SDK's default path: launches the native
  /// capture UI for an [ModularIdvHookPoint.onBefore] hook, or submits the capture result for an
  /// [ModularIdvHookPoint.onAfter] hook.
  ///
  /// [hookId] comes from a [ModularIdvHookEvent] and is single-use. Calling this twice for the same
  /// id, or after a new journey has started, throws a `PlatformException` rather than resuming
  /// twice.
  Future<bool> proceedModularIdvStep(String hookId) {
    return FlutterTsIdentityOrchestrationPlatform.instance.resumeModularIdvStep(
      hookId: hookId,
    );
  }

  /// Resumes a suspended acquisition step by submitting a client response instead of running the
  /// SDK's default path — for example cancelling capture, or taking a custom branch.
  ///
  /// [responseId] accepts the same values as [submitClientResponse], including custom branch ids.
  /// Same single-use semantics as [proceedModularIdvStep].
  Future<bool> submitModularIdvStep({
    required String hookId,
    required String responseId,
    Map<String, dynamic>? data,
  }) {
    return FlutterTsIdentityOrchestrationPlatform.instance.resumeModularIdvStep(
      hookId: hookId,
      responseId: responseId,
      data: data,
    );
  }
}
