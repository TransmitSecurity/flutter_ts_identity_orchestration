import Foundation
import IdentityOrchestration

/// Builds the error code and `details` payload the Dart layer receives for a native SDK failure.
///
/// This exists so every channel derives the code the same way. The plugin surfaces native errors on
/// two independent paths — the journey response stream and a failed method-channel call — and they
/// previously disagreed: the stream mapped known Modular IDV errors to their cross-platform string
/// code, while `FlutterError.details` carried only `localizedDescription`, so an app could not
/// branch on the cause of a failed `startJourney` at all.
///
/// `FlutterError.code` names the *operation* that failed (`startJourneyError`), which every cause of
/// that failure shares. The native error code is the part a caller can act on, so it travels in
/// `details` alongside the message.
enum NativeErrorPayload {

    /// The string error code for `error`, matching Android's `TSIdoErrorCode.error` values where the
    /// two platforms can express the same condition.
    ///
    /// Modular IDV failures are the case that matters and the case that needs unwrapping: they all
    /// arrive as `TSIdoJourneyError.internalError(IdoError)`, so without `IDVErrorMapping` they are
    /// indistinguishable from any other internal error. `TSIdoJourneyError` has **no** IDV cases of
    /// its own — unlike Android's `TSIdoErrorCode`, which declares eight — which is why the mapping
    /// is needed on this platform and not on the other.
    ///
    /// Anything not recognized falls back to `String(describing:)`, deliberately unchanged from the
    /// previous behaviour: inventing a code for an unknown error would be worse than describing it.
    static func code(for error: Error) -> String {
        if let journeyError = error as? TSIdoJourneyError,
           let idvCode = IDVErrorMapping.code(for: journeyError) {
            return idvCode
        }
        if let idoError = error as? IdoError,
           let idvCode = IDVErrorMapping.code(for: idoError) {
            return idvCode
        }
        return String(describing: error)
    }

    /// The `details` payload for a `FlutterError`, carrying both the actionable code and the message.
    static func details(for error: Error) -> [String: Any] {
        [
            "errorCode": code(for: error),
            "errorMessage": error.localizedDescription
        ]
    }
}
