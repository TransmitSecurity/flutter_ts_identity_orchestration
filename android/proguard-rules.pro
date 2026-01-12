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
