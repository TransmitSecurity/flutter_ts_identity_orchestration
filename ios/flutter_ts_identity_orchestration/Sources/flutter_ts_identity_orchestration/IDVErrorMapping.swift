import Foundation
import IdentityOrchestration

/// Maps the native iOS `IdoError.IDVError` constants onto the same string error codes the Android
/// SDK already exposes through `TSIdoErrorCode`, so Dart sees one shape on both platforms.
///
/// **Why comparison rather than reading the code.** `IdoError` is public and `Equatable`, but its
/// stored properties are not:
///
/// ```swift
/// public struct IdoError: Error, Equatable {
///     let errorCode: Int         // internal
///     let errorMessage: String   // internal
/// }
/// ```
///
/// From this module `error.errorCode` does not compile — the shipped `.swiftinterface` exposes
/// only `==` for `IdoError`, not even a memberwise init. The eight `IdoError.IDVError` constants
/// *are* public, so identity comparison is the one contractual way to recover which error occurred.
///
/// `String(describing:)` does leak the internal fields through Swift reflection, but a debug
/// description carries no stability guarantee across SDK or compiler versions, so it is not parsed
/// here. If the native SDK ever makes those properties public, this whole file collapses into
/// reading `errorCode` directly.
///
/// Known limitation: the mapping is a hardcoded mirror of the SDK's list. A ninth native IDV code
/// would return `nil` here and fall back to the generic journey-error path until this is updated.
enum IDVErrorMapping {

    /// Android's `TSIdoErrorCode` string values, so a Dart caller can branch identically on both
    /// platforms.
    private enum AndroidCode {
        static let cameraPermissionRequired = "idv_camera_permission_required"
        static let sdkDisabled = "idv_sdk_disabled"
        static let sessionNotValid = "idv_session_not_valid"
        static let initializationError = "idv_initialization_error"
        static let notInitialized = "idv_not_initialized"
        static let canceled = "idv_canceled"
        static let internalError = "idv_internal_error"
        static let notAvailable = "idv_not_available"
    }

    /// Returns the cross-platform string code for a Modular IDV error, or `nil` if `error` is not
    /// one of the known IDV constants — in which case the caller should fall back to its generic
    /// error handling rather than inventing a code.
    ///
    /// Note `IdoError.IDVError.internalError` (1007) is a different thing from the enum case
    /// `TSIdoJourneyError.internalError`, which is merely the wrapper every IDV failure arrives in.
    static func code(for error: IdoError) -> String? {
        switch error {
        case IdoError.IDVError.cameraPermissionRequired: return AndroidCode.cameraPermissionRequired
        case IdoError.IDVError.sdkDisabled:              return AndroidCode.sdkDisabled
        case IdoError.IDVError.sessionNotValid:          return AndroidCode.sessionNotValid
        case IdoError.IDVError.initializationError:      return AndroidCode.initializationError
        case IdoError.IDVError.notInitialized:           return AndroidCode.notInitialized
        case IdoError.IDVError.canceled:                 return AndroidCode.canceled
        case IdoError.IDVError.internalError:            return AndroidCode.internalError
        case IdoError.IDVError.notAvailable:             return AndroidCode.notAvailable
        default:                                         return nil
        }
    }

    /// Unwraps a journey error and returns the cross-platform IDV code when it wraps a known IDV
    /// failure. Every Modular IDV failure reaches the plugin as
    /// `TSIdoJourneyError.internalError(IdoError)`, so this is the only place an IDV code can be
    /// recovered from the journey callback.
    static func code(for journeyError: TSIdoJourneyError) -> String? {
        guard case let .internalError(idoError) = journeyError else { return nil }
        return code(for: idoError)
    }
}
