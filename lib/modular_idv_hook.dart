/// Discriminator carried by modular IDV hook events on the shared event channel. Must match
/// `MODULAR_IDV_HOOK_EVENT_TYPE` on Android and `ModularIDVHookBridge.hookEventType` on iOS.
const String modularIdvHookEventType = 'modularIdvHook';

/// Which modular IDV acquisition step a hook belongs to.
enum ModularIdvAcquisitionType {
  document,
  selfie;

  static ModularIdvAcquisitionType? _fromWire(Object? value) {
    switch (value) {
      case 'document':
        return ModularIdvAcquisitionType.document;
      case 'selfie':
        return ModularIdvAcquisitionType.selfie;
      default:
        return null;
    }
  }
}

/// Which side of the acquisition a hook fires on.
enum ModularIdvHookPoint {
  /// Before capture starts. Resuming with `proceed` launches the native capture UI.
  onBefore,

  /// After capture finishes, before the result is submitted. Resuming with `proceed` submits it.
  onAfter;

  static ModularIdvHookPoint? _fromWire(Object? value) {
    switch (value) {
      case 'onBefore':
        return ModularIdvHookPoint.onBefore;
      case 'onAfter':
        return ModularIdvHookPoint.onAfter;
      default:
        return null;
    }
  }
}

/// One client response option available at a suspended acquisition step.
///
/// Carries no `schema`: a hook chooses *which* branch to take rather than validating input against
/// a schema, and the full option — schema included — already arrives on the journey response for
/// this step.
class ModularIdvResponseOption {
  const ModularIdvResponseOption({
    required this.id,
    required this.label,
    required this.type,
  });

  final String id;
  final String label;
  final String type;

  static ModularIdvResponseOption _fromWire(Object? value) {
    final map = value is Map ? value : const <Object?, Object?>{};
    return ModularIdvResponseOption(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      type: map['type'] as String? ?? '',
    );
  }
}

/// A modular IDV acquisition step suspended in a hook, waiting for the app to resume it.
///
/// **The journey is stalled until you resume.** Call
/// [FlutterTsIdentityOrchestration.proceedModularIdvStep] to continue along the SDK's default path,
/// or [FlutterTsIdentityOrchestration.submitModularIdvStep] to branch the journey instead. Nothing
/// times this out: an event that is never resumed leaves the journey stopped at this step. That is
/// the native hook's own contract, not a plugin limitation.
///
/// [hookId] is single-shot. It is consumed by the first resume call, so a second call for the same
/// id fails rather than submitting twice.
///
/// Deliberately carries no IDV session token. The token that starts acquisition is a credential
/// only the native SDK can act on, so it is not sent across the platform channel.
class ModularIdvHookEvent {
  const ModularIdvHookEvent({
    required this.hookId,
    required this.hook,
    required this.acquisitionType,
    required this.acquisitionId,
    required this.responseOptions,
  });

  /// Opaque, single-use id identifying the suspended step. Pass it back when resuming.
  final String hookId;

  /// Whether this fired before or after capture.
  final ModularIdvHookPoint hook;

  /// Whether the suspended step is document or selfie acquisition.
  final ModularIdvAcquisitionType acquisitionType;

  /// The IDV acquisition session id, when the server supplied one.
  ///
  /// Nullable, and **not** a stable identifier for this event: the before and after hooks of one
  /// step share it, and it repeats across the document and selfie steps of a single journey. Use
  /// [hookId] to identify a step; use this only for correlation with server-side records.
  final String? acquisitionId;

  /// Response options available at this step, for use with
  /// [FlutterTsIdentityOrchestration.submitModularIdvStep]. May be empty.
  final List<ModularIdvResponseOption> responseOptions;

  /// True when [event] is a modular IDV hook event rather than a journey response.
  static bool isHookEvent(Map<String, dynamic> event) =>
      event['type'] == modularIdvHookEventType;

  /// Reads an event off the platform channel.
  ///
  /// Tolerant of missing or wrongly typed fields because the map arrives untyped from two separate
  /// native implementations: an unrecognized `hook` or `acquisitionType` yields `null` rather than
  /// throwing inside a stream, where an exception would tear down the subscription and strand every
  /// later hook. A `null` here means the event could not be understood and should be ignored — the
  /// step then stalls visibly instead of the whole stream dying silently.
  static ModularIdvHookEvent? fromEvent(Map<String, dynamic> event) {
    final hookId = event['hookId'] as String?;
    final hook = ModularIdvHookPoint._fromWire(event['hook']);
    final acquisitionType = ModularIdvAcquisitionType._fromWire(
      event['acquisitionType'],
    );

    if (hookId == null ||
        hookId.isEmpty ||
        hook == null ||
        acquisitionType == null) {
      return null;
    }

    final rawOptions = event['responseOptions'];
    return ModularIdvHookEvent(
      hookId: hookId,
      hook: hook,
      acquisitionType: acquisitionType,
      acquisitionId: event['acquisitionId'] as String?,
      responseOptions: rawOptions is List
          ? rawOptions.map(ModularIdvResponseOption._fromWire).toList()
          : const <ModularIdvResponseOption>[],
    );
  }
}
