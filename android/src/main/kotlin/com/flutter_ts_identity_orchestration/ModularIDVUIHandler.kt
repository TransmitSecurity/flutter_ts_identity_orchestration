package com.flutter_ts_identity_orchestration

import com.transmit.idosdk.modularidv.ITSUIHandler
import com.transmit.idosdk.modularidv.TSIDVStepHandler

/**
 * Modular IDV UI handler for the Android side of the plugin.
 *
 * Unlike iOS, registration is **not** required here for Modular IDV to work:
 * `IdoController.tryDispatchModularIDV` passes its nullable `uiHandler` straight through without a
 * null check, and `ModularIDVController` resolves absent hooks with `handler?.onBefore` followed by
 * `proceedSafely(...)`. So Android already launches capture and auto-proceeds with nothing
 * registered. Registering anyway is what lets both platforms share one code path and one hook seam;
 * iOS genuinely requires it.
 *
 * All hook policy lives in [ModularIDVHookBridge] — this type only routes the SDK's per-step
 * request to it, so document and selfie differ by one argument rather than by duplicated logic.
 * With no hooks enabled from Dart the bridge returns a bare [TSIDVStepHandler], which the SDK
 * treats as "proceed automatically": the pre-hook behaviour, unchanged.
 *
 * Deliberately not annotated `@Keep`, and deliberately not covered by a ProGuard rule. Nothing
 * resolves this class by name: `FlutterTsIdentityOrchestrationPlugin` is kept with `{ *; }` and
 * constructs it directly, and the SDK reaches the overrides through invoke-interface on the
 * already-kept `ITSUIHandler`, so R8 renaming it is harmless. Verified against `mapping.txt` from a
 * shrunk release build. `@Keep` would also require an `androidx.annotation` compile dependency this
 * module does not declare and cannot resolve from its configured repositories. See the comment
 * block in `android/proguard-rules.pro` for the three changes that would make a rule necessary.
 */
internal class ModularIDVUIHandler(private val hookBridge: ModularIDVHookBridge) : ITSUIHandler {

  override fun provideDocumentAcquisitionHandler(): TSIDVStepHandler =
    hookBridge.makeStepHandler(ModularIDVAcquisition.Document)

  override fun provideSelfieAcquisitionHandler(): TSIDVStepHandler =
    hookBridge.makeStepHandler(ModularIDVAcquisition.Selfie)
}
