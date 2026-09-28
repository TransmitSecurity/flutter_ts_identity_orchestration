# Flutter TS Identity Orchestration Plugin ProGuard Rules
# These rules prevent R8/ProGuard from removing classes needed by the Transmit Security IDO SDK

# Keep all Transmit Security IDO SDK classes
-keep class com.transmit.idosdk.** { *; }
-keepclassmembers class com.transmit.idosdk.** { *; }

# Keep TSIdoCallback interface and its implementations (including DefaultImpls)
-keep interface com.transmit.idosdk.TSIdoCallback { *; }
-keep class com.transmit.idosdk.TSIdoCallback$* { *; }
-keepclassmembers interface com.transmit.idosdk.TSIdoCallback { *; }

# Keep TSIdoInstruction class (used via reflection in handleInstructions)
-keep class com.transmit.idosdk.TSIdoInstruction { *; }
-keepclassmembers class com.transmit.idosdk.TSIdoInstruction { *; }

# Keep TSIdoServiceResponse class
-keep class com.transmit.idosdk.TSIdoServiceResponse { *; }
-keepclassmembers class com.transmit.idosdk.TSIdoServiceResponse { *; }

# Keep other essential IDO SDK classes
-keep class com.transmit.idosdk.TSIdo { *; }
-keep class com.transmit.idosdk.TSIdoSdkError { *; }
-keep class com.transmit.idosdk.TSIdoInitOptions { *; }
-keep class com.transmit.idosdk.TSIdoStartJourneyOptions { *; }
-keep class com.transmit.idosdk.TSIdoClientResponseOptionType { *; }
-keep class com.transmit.idosdk.TSIdoEncryptionMode { *; }
-keep class com.transmit.idosdk.TSPushTokenType { *; }

# Kotlin specific rules for interface default implementations
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keepclassmembers class ** {
    synthetic <methods>;
}

# Keep plugin classes that use reflection
-keep class com.flutter_ts_identity_orchestration.FlutterTsIdentityOrchestrationPlugin { *; }
-keepclassmembers class com.flutter_ts_identity_orchestration.FlutterTsIdentityOrchestrationPlugin {
    private void handleInstructions(com.transmit.idosdk.TSIdoInstruction);
    private ** convertJsonToFlutterCompatible(**);
}

# Preserve annotations and their default values
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep names for reflection usage
-keepattributes LocalVariableTable,LocalVariableTypeTable

# Prevent obfuscation of classes used by reflection
-keepnames class com.transmit.idosdk.TSIdoInstruction
-keepclassmembernames class com.transmit.idosdk.TSIdoInstruction { *; }

# General rules for JSON processing (used in convertJsonToFlutterCompatible)
-keep class org.json.** { *; }
-dontwarn org.json.**

# Suppress warnings for missing classes that might be optional
-dontwarn com.transmit.idosdk.**

# ---------------------------------------------------------------------------
# Shared core (com.ts.coresdk) - device data collection, used by collectRiskData
#
# WHY THIS IS HERE: neither dependency ships consumer rules of its own. The IDO
# SDK declares consumerProguardFiles "consumer-rules.pro" but that file is EMPTY
# at 1.0.32, and the core SDK declares no consumerProguardFiles at all. This
# file is therefore the ONLY consumer rule set that reaches an integrating app,
# and before this it covered com.transmit.idosdk.** but nothing under
# com.ts.coresdk.**.
#
# Enabling collectRiskData (added in IDO Android 1.0.32 / core 1.0.28) runs the
# core device-data collectors, whose models are serialized reflectively. Without
# these keeps the feature works in a debug build and can fail in a consumer's
# R8 release build - a failure mode invisible to this repo's own builds.
#
# The keeps below mirror what core keeps for ITSELF in its own obfuscation
# config, which is the best available evidence of what must survive shrinking.
# ---------------------------------------------------------------------------

-keep class com.ts.coresdk.device.TSDeviceDataCollector {
  <methods>;
}

-keep interface com.ts.coresdk.device.ITSDeviceDataCollector {
  *;
}

# Device data models are serialized to the citadel payload by name.
-keep class com.ts.coresdk.device.model.** {
  *;
}

-keep enum com.ts.coresdk.device.model.TSDeviceDataAttributeKey {
  *;
}

# Geolocation providers are selected at runtime by GeolocationProviderFactory and
# depend on optional Play Services classes.
-keep class com.ts.coresdk.geolocation.** {
  *;
}

-keep interface com.ts.coresdk.geolocation.provider.TSGeolocationProvider {
  *;
}

# Citadel payload models on the IDO side are already covered by the
# com.transmit.idosdk.** keeps above.

# play-services-location arrives transitively via core 1.0.28. It is optional at
# runtime - the SDK falls back to a non-fused provider - so missing classes must
# not fail the build for consumers who exclude it.
-dontwarn com.google.android.gms.**
-dontwarn com.ts.coresdk.**

# ---------------------------------------------------------------------------
# Modular IDV (com.ts.sdk:identityverification)
#
# Linking this dependency (required for ido-android-sdk's Modular IDV dispatch to work
# at runtime) causes R8 to keep Flutter's Play Store deferred-components code path,
# which was previously tree-shaken away as unreached. That path references Play Core
# split-install classes that most apps - including this plugin's own example app -
# never bundle, since they don't use deferred components. Suppress rather than keep:
# these classes are genuinely optional, not something a consumer needs at runtime.
# ---------------------------------------------------------------------------

-dontwarn com.google.android.play.core.**

# ---------------------------------------------------------------------------
# ModularIDVUIHandler and ModularIDVHookBridge need NO rule - deliberately.
#
# They survive R8 without one: FlutterTsIdentityOrchestrationPlugin is kept with
# { *; } above, its field initializers instantiate ModularIDVHookBridge and
# ModularIDVUIHandler directly, and a class R8 can see being constructed is not
# stripped. The handler's two overrides survive via invoke-interface on
# ITSUIHandler, itself kept by com.transmit.idosdk.**. The onBefore/onAfter
# closures survive as assignments to TSIDVStepHandler's Function1 fields, also
# covered by that keep. R8 may rename any of it - harmless, since nothing
# resolves these types by name.
#
# The Dart hook bridge specifically does NOT need a rule. It keys suspended steps
# by a runtime-generated UUID mapped to a live context reference, not by class or
# member name, so obfuscation cannot break the lookup. Verified against
# mapping.txt from a shrunk release build: every type is present with its members
# renamed, confirming shrinking was active rather than skipped.
#
# Add a keep here only if that stops being true:
#   - either class is constructed reflectively, or registered from the manifest/DI
#   - the hook registry starts keying on a class or member NAME rather than a
#     generated id
#   - the hook event or resume payload gains a type serialized by field name
#     (Gson/Moshi/kotlinx), which would need its fields kept
#   - the FlutterTsIdentityOrchestrationPlugin keep above is narrowed from { *; }
#     to a member list, which would break the reachability chain
# ---------------------------------------------------------------------------
