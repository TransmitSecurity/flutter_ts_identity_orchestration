import Foundation
import IdentityOrchestration

/// Which modular IDV acquisition step a hook belongs to.
enum ModularIDVAcquisition: String {
    case document
    case selfie
}

/// Which side of the acquisition a hook fires on.
enum ModularIDVHookPoint: String {
    case onBefore
    case onAfter
}

/// How Dart wants a suspended step to continue.
enum ModularIDVResume {
    /// Run the SDK's default flow: start capture (`onBefore`) or submit the result (`onAfter`).
    case proceed

    /// Bypass the default flow and submit `option` instead, branching the journey.
    ///
    /// The option arrives already converted from the raw Dart id by the caller — this bridge
    /// deliberately knows nothing about that mapping, which the plugin already owns.
    case submit(option: TSIdoClientResponseOptionType, data: [String: Any]?)
}

/// Outcome of a resume attempt, so the caller can shape a channel reply without catching.
enum ModularIDVResumeResult {
    case resumed

    /// No pending hook for the given id: never issued, already consumed, or cleared by a new journey.
    case unknownHookId

    /// The SDK rejected the resume. The hook is consumed regardless — retrying it cannot succeed.
    case failed(Error)
}

/// Bridges the native SDK's **synchronous** modular IDV hooks to Dart's **asynchronous** platform
/// channel.
///
/// This is only possible because of a specific property of the SDK contract: `onBefore`/`onAfter`
/// are `TSHandlerCallback<Input, Void>`, and `ModularIDVController` does nothing at all once a hook
/// returns. The step resumes solely through `TSIdoStepContext.proceed()` or `.submit(option:data:)`.
/// So a hook is fire-and-forget — the bridge can store the context, emit an event, return
/// immediately, and resume the journey much later when Dart calls back. A hook that *returned* a
/// decision could not be bridged this way.
///
/// The consequence, which is inherent and not a defect: while a hook is pending the journey is
/// **stalled**. Nothing times it out. If Dart never resumes, the step never completes — exactly the
/// semantics a native app gets from these hooks.
///
/// ### Hooks are opt-in, and must stay that way
///
/// A nil hook means "proceed automatically", which is the behaviour every existing integration
/// relies on. Installing hooks unconditionally would stall every acquisition step in every app that
/// does not listen — a silent hang, not an error. So `setEnabled` defaults to off and
/// `makeStepHandler` installs only the hooks explicitly enabled from Dart.
///
/// ### Identity across the channel
///
/// A `TSIDVAcquisitionContext` cannot cross a platform channel, and there is nothing in the step
/// data that reliably identifies one: `acquisitionId` is optional, is reused by the before and after
/// hook of the same step, and repeats across the document and selfie steps of one journey. So each
/// hook invocation is assigned a fresh opaque `hookId` and the context is held here. Ids are
/// **single-shot** — consumed on first resume — so a double reply from Dart cannot submit twice.
///
/// ### Difference from Android, absorbed here
///
/// `proceed()` and `submit(option:data:)` are `throws` on this platform and non-throwing on Android,
/// and `submit` takes a `TSIdoClientResponseOptionType` rather than a `String`. Both differences are
/// resolved inside this file so the Dart-facing contract is identical on the two platforms.
final class ModularIDVHookBridge {

    /// Emits a hook event to Dart. Injected rather than referencing the channel directly, which
    /// keeps this type free of Flutter and independently testable.
    private let emit: ([String: Any]) -> Void

    /// Pending contexts by hook id.
    ///
    /// Guarded by `lock` because hooks are invoked from the SDK's dispatch path — `onBefore`
    /// synchronously from the IDO controller, `onAfter` from the IDV SDK's completion — while
    /// resumes arrive on the platform-channel thread. Entries are removed on resume or by `reset()`;
    /// a stalled journey leaves at most one entry per in-flight step, cleared at the next journey
    /// start.
    private var pending: [String: any TSIDVAcquisitionContext] = [:]

    private var onBeforeEnabled = false
    private var onAfterEnabled = false

    private let lock = NSLock()

    /// Discriminator on the shared event channel, matched by the Dart side and by Android.
    static let hookEventType = "modularIdvHook"

    init(emit: @escaping ([String: Any]) -> Void) {
        self.emit = emit
    }

    /// Enables or disables each hook.
    ///
    /// Takes effect from the next acquisition step, not the current one: handlers are produced per
    /// step by `makeStepHandler`, but a step already suspended in a hook keeps the behaviour it
    /// started with. Disabling while a hook is pending does not resume it — `reset()` or an explicit
    /// resume is still required, otherwise that journey stays stalled.
    func setEnabled(onBefore: Bool, onAfter: Bool) {
        lock.lock()
        defer { lock.unlock() }

        onBeforeEnabled = onBefore
        onAfterEnabled = onAfter
    }

    /// True when at least one hook is enabled, so callers can report the live configuration back.
    func isEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return onBeforeEnabled || onAfterEnabled
    }

    /// Drops every pending hook.
    ///
    /// Called at journey start. Contexts from a previous journey are already unusable — their
    /// proceed/submit closures target a step the SDK has moved past — so retaining them would only
    /// let Dart resume a dead step and leak the closures for the plugin's lifetime.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        pending.removeAll()
    }

    /// Builds the handler for one acquisition step, installing only the enabled hooks.
    ///
    /// A fresh `TSIDVStepHandler` per call is deliberate: the SDK asks for a handler per step, and
    /// the closures capture `acquisition` so the emitted event can say which step is suspended.
    func makeStepHandler(for acquisition: ModularIDVAcquisition) -> TSIDVStepHandler {
        let handler = TSIDVStepHandler()

        lock.lock()
        let installOnBefore = onBeforeEnabled
        let installOnAfter = onAfterEnabled
        lock.unlock()

        if installOnBefore {
            handler.onBefore = { [weak self] context in
                self?.suspendStep(acquisition, .onBefore, context)
            }
        }

        if installOnAfter {
            handler.onAfter = { [weak self] context in
                self?.suspendStep(acquisition, .onAfter, context)
            }
        }

        return handler
    }

    /// Resumes the step held under `hookId`, consuming the id.
    ///
    /// The id is consumed before the SDK call, not after: proceed/submit can throw, and a hook that
    /// failed to resume cannot be resumed again — the SDK has already delivered the failure through
    /// the journey callback. Leaving the id live would invite a retry that silently does nothing.
    func resume(hookId: String, action: ModularIDVResume) -> ModularIDVResumeResult {
        lock.lock()
        let context = pending.removeValue(forKey: hookId)
        lock.unlock()

        guard let context else { return .unknownHookId }

        do {
            switch action {
            case .proceed:
                try context.proceed()
            case let .submit(option, data):
                try context.submit(option: option, data: data)
            }
            return .resumed
        } catch {
            return .failed(error)
        }
    }

    /// Registers `context` under a fresh id and tells Dart the step is waiting.
    private func suspendStep(
        _ acquisition: ModularIDVAcquisition,
        _ hookPoint: ModularIDVHookPoint,
        _ context: any TSIDVAcquisitionContext
    ) {
        let hookId = UUID().uuidString

        lock.lock()
        pending[hookId] = context
        lock.unlock()

        emit(hookEvent(hookId: hookId, acquisition: acquisition, hookPoint: hookPoint, context: context))
    }

    /// Shapes the event Dart receives.
    ///
    /// Two fields of `TSAcquisitionStepData` are withheld on purpose:
    ///
    /// - **`startToken`** is a live IDV session credential. Dart cannot act on it — only the native
    ///   SDK can start acquisition — so putting it on the channel would widen a secret's blast
    ///   radius for no capability. Android withholds it identically.
    /// - **`state` and `baseEndpoint`** are hardcoded to nil by the SDK's own step decoding at this
    ///   version, on both platforms. Emitting always-null keys would imply a contract the SDK does
    ///   not have yet.
    ///
    /// `NSNull()` rather than an omitted key for a nil `acquisitionId`, so Dart sees the same
    /// explicit null Android's nullable map value produces.
    private func hookEvent(
        hookId: String,
        acquisition: ModularIDVAcquisition,
        hookPoint: ModularIDVHookPoint,
        context: any TSIDVAcquisitionContext
    ) -> [String: Any] {
        return [
            "type": Self.hookEventType,
            "hookId": hookId,
            "hook": hookPoint.rawValue,
            "acquisitionType": acquisition.rawValue,
            "acquisitionId": context.data.acquisitionId ?? NSNull(),
            "responseOptions": (context.data.responseOptions ?? []).map { responseOption($0) }
        ]
    }

    /// Flattens one response option for the channel.
    ///
    /// `schema` is omitted: it is the only non-primitive field, and a hook decides *which* branch to
    /// take rather than validating input against a schema. The full option, schema included, already
    /// reaches Dart on the journey response for this step.
    private func responseOption(_ option: any TSIdoClientResponseOption) -> [String: Any] {
        return [
            "id": option.id,
            "label": option.label,
            "type": String(describing: option.type)
        ]
    }
}
