import Foundation
import IdentityOrchestration

/// Registers the plugin as the Modular IDV UI handler so document/selfie acquisition steps are
/// driven by the native SDK instead of being forwarded to Dart as unhandled journey steps.
///
/// **Registration is not optional on iOS.** `IdentityOrchestrationController` dispatches an
/// acquisition step only when a UI handler is present:
///
/// ```swift
/// case .documentAcquisition:
///     if let uiHandler { /* start capture */ } else { notifyJourneyResponse(...) }
/// ```
///
/// With no handler registered the step is delivered to the app as a plain journey response, no
/// capture UI appears, and nothing errors. Android differs — `IdoController.tryDispatchModularIDV`
/// never null-checks its handler, so Modular IDV works there with nothing registered. Registering
/// here is what makes the two platforms behave the same.
///
/// All hook policy lives in `ModularIDVHookBridge` — this type only routes the SDK's per-step
/// request to it, so document and selfie differ by one argument rather than by duplicated logic.
/// With no hooks enabled from Dart the bridge returns a bare `TSIDVStepHandler`, which both SDKs
/// treat as "proceed automatically": the pre-hook behaviour, unchanged.
final class ModularIDVUIHandler: ITSUIHandler {

    private let hookBridge: ModularIDVHookBridge

    init(hookBridge: ModularIDVHookBridge) {
        self.hookBridge = hookBridge
    }

    func provideDocumentAcquisitionHandler() -> TSIDVStepHandler {
        return hookBridge.makeStepHandler(for: .document)
    }

    func provideSelfieAcquisitionHandler() -> TSIDVStepHandler {
        return hookBridge.makeStepHandler(for: .selfie)
    }
}
