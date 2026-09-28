package com.flutter_ts_identity_orchestration

import android.R
import android.content.Context
import android.util.Log
import com.transmit.idosdk.Escape
import com.transmit.idosdk.TSIdo
import com.transmit.idosdk.TSIdoCallback
import com.transmit.idosdk.TSIdoClientResponseOptionType
import com.transmit.idosdk.TSIdoEncryptionMode
import com.transmit.idosdk.TSIdoErrorCode
import com.transmit.idosdk.TSIdoInitOptions
import com.transmit.idosdk.TSIdoInstruction
import com.transmit.idosdk.TSIdoSdkError
import com.transmit.idosdk.TSIdoServiceResponse
import com.transmit.idosdk.TSIdoStartJourneyOptions
import com.transmit.idosdk.TSPushTokenType
import org.json.JSONArray
import org.json.JSONObject
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * The single source of the string error code the Dart layer sees, on every channel.
 *
 * Always [TSIdoErrorCode.error] — the SDK's own snake_case wire value, e.g. `idv_not_available` —
 * never the Kotlin enum name. `TSIdoErrorCode` declares no `toString()` override, so
 * `errorCode.toString()` yields the constant name (`IdvNotAvailable`) instead, which is not what
 * UserGuide.md documents and not what iOS emits. Reading `.error` in exactly one place is what
 * keeps the journey-response path and the method-channel error path from drifting apart again.
 *
 * File-level rather than a member so it is one concept with one definition, usable from the
 * plugin's tests without an instance.
 */
internal val TSIdoErrorCode.dartCode: String get() = error

/** FlutterTsIdentityOrchestrationPlugin */
class FlutterTsIdentityOrchestrationPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

  enum class IdentityOrchestrationPluginError(val rawValue: String) {
    InvalidArguments("invalidArguments"),
    SdkInitError("sdkInitError"),
    StartJourneyError("startJourneyError"),
    StartMobileApproveError("startMobileApproveError"),
    SubmitResponseError("submitResponseError"),
    GenerateDebugPINError("generateDebugPINError"),
    ModularIdvHookError("modularIdvHookError")
  }

  private companion object {
    private const val TAG = "TSIdoPlugin"

    /**
     * The native Android IDO SDK version this plugin wraps. Used by
     * [logNotImplementedOnAndroid] so the log names the version that lacks the API,
     * rather than saying "not implemented" without a reference point.
     */
    private const val NATIVE_SDK_VERSION = "1.0.34"
  }

  /**
   * Owns modular IDV hook state: which hooks Dart enabled, and the contexts of steps currently
   * suspended in one. Emits onto the shared event channel.
   */
  internal val modularIDVHookBridge = ModularIDVHookBridge { event -> eventSink?.success(event) }

  /**
   * Modular IDV UI handler. Held for the plugin's lifetime rather than created per call, so the
   * same instance is re-registered before every journey — see [registerModularIDVUIHandler].
   */
  private val modularIDVUIHandler = ModularIDVUIHandler(modularIDVHookBridge)

  /**
   * Registers the Modular IDV UI handler immediately before starting a journey.
   *
   * Called per journey start rather than once at init, matching both native demo apps. The
   * ordering is load-bearing on this platform: `TSIdo.setUIHandler` also clears the cached
   * `ModularIDVController`, which holds the `start_token` reused across the document and selfie
   * steps of a single journey — registering mid-journey would discard it.
   *
   * Registration is a no-op behaviourally on Android, which dispatches acquisition steps whether
   * or not a handler is present. It is done anyway so both platforms share one code path; iOS
   * genuinely requires it. See [ModularIDVUIHandler].
   *
   * Pending hooks are dropped here rather than at journey end, because a journey has no single
   * end: it can complete, error, or simply be abandoned. Starting the next one is the only point
   * where the previous journey's suspended steps are provably dead.
   */
  private fun registerModularIDVUIHandler() {
    modularIDVHookBridge.reset()
    TSIdo.setUIHandler(modularIDVUIHandler)
  }

  /** Enables or disables the modular IDV hooks. Both default to off. */
  private fun handleSetModularIdvHooks(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    if (arguments == null) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Error configuring modular IDV hooks. Invalid arguments provided",
        null
      )
      return
    }

    modularIDVHookBridge.setEnabled(
      onBefore = arguments["onBefore"] as? Boolean ?: false,
      onAfter = arguments["onAfter"] as? Boolean ?: false
    )
    result.success(true)
  }

  /**
   * Resumes a suspended acquisition step, either along the SDK's default path or by submitting a
   * client response that branches the journey.
   *
   * `responseId` is converted with the same mapping [handleSubmitClientResponse] uses, so a hook
   * response and a normal one behave identically for the same Dart id — including the `Custom`
   * fallback, which forwards the raw id rather than the enum's own type string.
   */
  private fun handleResumeModularIdvStep(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    val hookId = arguments?.get("hookId") as? String

    if (hookId.isNullOrEmpty()) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Hook id is required",
        null
      )
      return
    }

    val rawResponseId = arguments["responseId"] as? String
    val action = if (rawResponseId.isNullOrEmpty()) {
      ModularIDVResume.Proceed
    } else {
      val responseOptionType = convertResponseOptionId(rawResponseId)
      val responseId =
        if (responseOptionType == TSIdoClientResponseOptionType.Custom) rawResponseId
        else responseOptionType.type
      ModularIDVResume.Submit(responseId, arguments["data"] as? Map<String, Any>)
    }

    when (val outcome = modularIDVHookBridge.resume(hookId, action)) {
      is ModularIDVResumeResult.Resumed -> result.success(true)
      is ModularIDVResumeResult.UnknownHookId -> result.error(
        IdentityOrchestrationPluginError.ModularIdvHookError.rawValue,
        "No modular IDV step is waiting for this hook id",
        "It was already resumed, or a new journey was started since it was issued"
      )
      is ModularIDVResumeResult.Failed -> result.error(
        IdentityOrchestrationPluginError.ModularIdvHookError.rawValue,
        "Failed to resume modular IDV step",
        outcome.cause.message
      )
    }
  }

  /**
   * Normalizes the `collectRiskData` init option.
   *
   * Absent, null, or a non-Boolean value all resolve to `false`, matching the native
   * SDK default. Extracted so the coercion is unit-testable without a live SDK: the
   * options map arrives from Dart untyped, so a wrong type is a realistic input rather
   * than a theoretical one.
   */
  internal fun parseCollectRiskData(options: Map<String, Any>?): Boolean =
    options?.get("collectRiskData") as? Boolean ?: false

  /**
   * Normalizes the `drsSessionToken` journey option.
   *
   * Returns null for absent, null, non-String, empty and blank values, and **trims** surrounding
   * whitespace from anything it does return. The native iOS SDK appends the DRS header only for a
   * non-empty token, so an empty string must be indistinguishable from omission on both platforms.
   *
   * Trimming matters for parity, not just tidiness: this previously returned the raw string, so
   * `" abc "` was sent verbatim on Android while iOS sent `"abc"` — the same Dart input produced
   * two different headers, and the padded one would not match server-side. Both platforms now
   * trim.
   */
  internal fun parseDrsSessionToken(options: Map<String, Any>?): String? =
    (options?.get("drsSessionToken") as? String)?.trim()?.takeIf { it.isNotEmpty() }

  /**
   * The `details` payload for a failed method-channel call carrying a native SDK error.
   *
   * `PlatformException.code` identifies the *operation* that failed (`startJourneyError`), which is
   * too coarse to act on: every cause of a failed start-journey shares it. The native `errorCode`
   * is what a caller can actually branch on, so it travels in `details` alongside the message.
   *
   * These call sites previously passed `null`, discarding an error code the SDK had already
   * supplied. An app could not distinguish a missing IDV SDK from a network failure without
   * substring-matching the message.
   */
  internal fun errorDetails(error: TSIdoSdkError): Map<String, Any> = mapOf(
    "errorCode" to error.errorCode.dartCode,
    "errorMessage" to error.errorMessage
  )

  /**
   * Reports that an API exists in the plugin's cross-platform surface but has no
   * Android implementation at the wrapped native version.
   *
   * The Dart API is intentionally identical on both platforms so consumer code needs no
   * platform branching. Where Android's native SDK cannot express an API that iOS can,
   * the call is accepted and this is logged, rather than the method being absent (which
   * would force branching) or failing silently (which would hide the gap).
   */
  private fun logNotImplementedOnAndroid(api: String) {
    Log.w(TAG, "$api: not implemented in SDK $NATIVE_SDK_VERSION")
  }

  /** Guards the [logNotImplementedOnAndroid] call for `TSIdoServiceResponse.code`. */
  private var loggedMissingResponseCode = false

  private lateinit var applicationContext: Context
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel : EventChannel
  private var eventSink: EventChannel.EventSink? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_ts_identity_orchestration")
    channel.setMethodCallHandler(this)
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_ts_identity_orchestration_events")
    eventChannel.setStreamHandler(this)
    this.applicationContext = flutterPluginBinding.applicationContext;
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "initializeSDK") {
      handleInitializeSDK(call, result)
    } else if (call.method == "initialize") {
      handleInitialize(call, result)
    } else if (call.method == "startJourney") {
      handleStartJourney(call, result)
    } else if (call.method == "submitClientResponse") {
      handleSubmitClientResponse(call, result)
    } else if (call.method == "generateDebugPin") {
      handleGenerateDebugPin(call, result)
    } else if (call.method == "startMobileApproveJourney") {
      handleStartMobileApproveJourney(call, result)
    } else if (call.method == "setLoggingEnabled") {
      handleSetLoggingEnabled(call, result)
    } else if (call.method == "setPushToken") {
      handleSetPushToken(call, result)
    } else if (call.method == "setModularIdvHooks") {
      handleSetModularIdvHooks(call, result)
    } else if (call.method == "resumeModularIdvStep") {
      handleResumeModularIdvStep(call, result)
    } else {
      result.notImplemented()
    }
  }

  private fun handleInitializeSDK(call: MethodCall, result: Result) {
    try {
      TSIdo.initializeSDK(this.applicationContext)
      result.success(true)
    } catch (e: Exception) {
      result.error(
        IdentityOrchestrationPluginError.SdkInitError.rawValue,
        "Failed to initialize SDK",
        "${e.message}"
      )
    }
  }

  private fun handleInitialize(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    if (arguments == null) {
      result.error("INVALID_ARGUMENTS", "Invalid arguments", null)
      return
    }

    val clientId = arguments["clientId"] as? String ?: ""
    val options = arguments["options"] as? Map<String, Any>

    if (clientId.isEmpty()) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Error initializing the SDK",
        "Invalid client identifier provided")
      return
    }

    val serverPath = options?.get("serverPath") as? String ?: "https://api.transmitsecurity.io"
    val resource = options?.get("resource") as? String
    val pollingTimeout = options?.get("pollingTimeout") as? Int
    val locale = options?.get("locale") as? String
    val collectRiskData = parseCollectRiskData(options)

    try {
      val initOptions = TSIdoInitOptions(
        serverPath = serverPath,
        resourceUri = resource,
        pollingTimeout = pollingTimeout,
        locale = locale,
        collectRiskData = collectRiskData
      )
      TSIdo.initializeSDK(this.applicationContext, clientId, initOptions);
      result.success(mapOf("success" to true, "message" to "SDK initialized successfully"))
    } catch (e: Exception) {
      result.error(
        IdentityOrchestrationPluginError.SdkInitError.rawValue,
        "Failed to initialize SDK",
        "${e.message}"
      )
    }
  }

  private fun handleStartJourney(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    if (arguments == null) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Error starting journey. Invalid arguments provided",
        null
      )
      return
    }

    val journeyId = arguments["journeyId"] as? String ?: ""
    if (journeyId.isEmpty()) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Journey ID is required",
        null
      )
      return
    }

    val options = arguments["options"] as? Map<String, Any>
    val additionalParams = options?.get("additionalParams") as? Map<String, Any>
    val flowId = options?.get("flowId") as? String
    val drsSessionToken = parseDrsSessionToken(options)

    val journeyEncryptionMode: TSIdoEncryptionMode? = when (options?.get("encryptionMode") as? Boolean) {
      true -> TSIdoEncryptionMode.Full
      false -> TSIdoEncryptionMode.None
      null -> null
    }

    val startJourneyOptions = TSIdoStartJourneyOptions(
      additionalParams = additionalParams,
      flowId = flowId,
      encryptionMode = journeyEncryptionMode,
      drsSessionToken = drsSessionToken
    )

    try {
      registerModularIDVUIHandler()
      TSIdo.startJourney(
        journeyId,
        startJourneyOptions,
        object: TSIdoCallback<TSIdoServiceResponse>{
          override fun idoSuccess(response: TSIdoServiceResponse) {
            handleIdoSuccess(response)
            result.success(true)
          }
          override fun idoError(error: TSIdoSdkError) {
            result.error(
              IdentityOrchestrationPluginError.StartJourneyError.rawValue,
              "Failed to start journey: ${error.errorMessage}",
              errorDetails(error)
            )
          }

          override fun idoInstruction(instruction: TSIdoInstruction) {
            handleInstructions(instruction)
          }
        }
      )
    } catch (e: Exception) {
      result.error(
        IdentityOrchestrationPluginError.StartJourneyError.rawValue,
        "Failed to start journey: ${e.message}",
        null
      )
    }
  }

  private fun handleStartMobileApproveJourney(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    if (arguments == null) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Error starting mobile approve journey. Invalid arguments provided",
        null
      )
      return
    }

    val payload = arguments["payload"] as? Map<String, String>
    val startJourneyOptions = arguments["startJourneyOptions"] as? Map<String, Any>

    if (payload == null) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Payload is required",
        null
      )
      return
    }

    try {
      val options = convertStartJourneyOptions(startJourneyOptions)

      registerModularIDVUIHandler()
      TSIdo.startMobileApproveJourney(
        payload,
        options,
        object : TSIdoCallback<TSIdoServiceResponse> {
          override fun idoSuccess(response: TSIdoServiceResponse) {
            handleIdoSuccess(response)
            result.success(true)
          }

          override fun idoError(error: TSIdoSdkError) {
            result.error(
              IdentityOrchestrationPluginError.StartMobileApproveError.rawValue,
              "Failed to start mobile approve journey: ${error.errorMessage}",
              errorDetails(error)
            )
          }

          override fun idoInstruction(instruction: TSIdoInstruction) {
            handleInstructions(instruction)
          }
        }
      )
    } catch (e: Exception) {
      result.error(
        IdentityOrchestrationPluginError.StartMobileApproveError.rawValue,
        "Failed to start mobile approve journey",
        e.message
      )
    }
  }

  private fun handleSetPushToken(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    val token = arguments?.get("token") as? String

    if (token == null || token.isEmpty()) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Invalid arguments for setPushToken",
        "Token parameter is required and cannot be empty"
      )
      return
    }

    TSIdo.setPushToken(token, TSPushTokenType.Fcm);

    result.success(true)
  }

  private fun handleSubmitClientResponse(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    if (arguments == null) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Error submitting client response. Invalid arguments provided",
        null
      )
      return
    }

    val rawResponseId = arguments["responseId"] as? String ?: ""
    if (rawResponseId.isEmpty()) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Response id is required",
        null
      )
      return
    }

    var responseId = convertResponseOptionId(rawResponseId)
    val data = arguments["data"] as? Map<String, Any>

    var responseType = responseId.type
    if (responseId == TSIdoClientResponseOptionType.Custom) {
      responseType = rawResponseId
    }

    TSIdo.submitClientResponse(responseType, data,
      object: TSIdoCallback<TSIdoServiceResponse>{

        override fun idoSuccess(response: TSIdoServiceResponse) {
          handleIdoSuccess(response)
          result.success(true)
        }

        override fun idoError(error: TSIdoSdkError) {
          result.error(
            IdentityOrchestrationPluginError.SubmitResponseError.rawValue,
            "Error during submit response: ${error.errorMessage}",
            errorDetails(error)
          )
        }

        override fun idoInstruction(instruction: TSIdoInstruction) {
          handleInstructions(instruction)
        }
      }
    )
  }

  private fun handleInstructions(instruction: TSIdoInstruction) {
    val instructionDict = hashMapOf<String, Any>()
    
    // Convert TSIdoInstruction to Flutter-compatible format safely
    try {
      // Use reflection to safely extract all properties from TSIdoInstruction
      val clazz = instruction::class.java
      val fields = clazz.declaredFields
      
      for (field in fields) {
        try {
          field.isAccessible = true
          val value = field.get(instruction)
          if (value != null) {
            // Convert the value to Flutter-compatible format
            instructionDict[field.name] = convertToFlutterCompatible(value)
          }
        } catch (e: Exception) {
          // Skip fields that can't be accessed
        }
      }
      
      // If no fields were extracted, try toString() for basic representation
      if (instructionDict.isEmpty()) {
        instructionDict["data"] = instruction.toString()
      }
      
    } catch (e: Exception) {
      // Fallback: just provide basic info
      instructionDict["type"] = "instruction"
      instructionDict["data"] = instruction.toString()
    }
    
    val instructionEvent = hashMapOf<String, Any>(
      "type" to "instructions",
      "instructions" to instructionDict
    )
    
    eventSink?.success(instructionEvent)
  }

  // Enhanced conversion function to handle all types including enums
  private fun convertToFlutterCompatible(value: Any?): Any {
    return when (value) {
      is JSONObject -> convertJsonToFlutterCompatible(value)
      is JSONArray -> convertJsonToFlutterCompatible(value)
      is String, is Int, is Double, is Boolean -> value
      is Enum<*> -> value.toString() // Convert enums to string
      is Map<*, *> -> {
        val map = hashMapOf<String, Any>()
        for (entry in value.entries) {
          val key = entry.key
          val entryValue = entry.value
          if (key is String) {
            map[key] = convertToFlutterCompatible(entryValue)
          }
        }
        map
      }
      is List<*> -> {
        val list = arrayListOf<Any>()
        for (item in value) {
          list.add(convertToFlutterCompatible(item))
        }
        list
      }
      null -> ""
      else -> value.toString() // Convert any other type to string
    }
  }

  private fun handleIdoSuccess(response: TSIdoServiceResponse) {
    val responseDict = hashMapOf<String, Any>()
    
    // Add data if available - convert JSON objects/arrays to Flutter-compatible types
    response.data?.let { data ->
      responseDict["data"] = convertJsonToFlutterCompatible(data)
    }
    
    response.journeyStepId?.let { stepId ->
      responseDict["journeyStepId"] = stepId.toString()
    }
    
    response.clientResponseOptions?.let { options ->
      val optionsDict = hashMapOf<String, Map<String, Any>>()
      options.forEach { (key, option) ->
        val optionDict = hashMapOf<String, Any>(
          "id" to option.id,
          "label" to option.label,
          "type" to option.type.toString()
        )
        option.schema?.let { schema ->
          optionDict["schema"] = convertJsonToFlutterCompatible(schema)
        }
        optionsDict[key] = optionDict
      }
      responseDict["clientResponseOptions"] = optionsDict
    }
    
    // Add token if available
    response.token?.let { token ->
      responseDict["token"] = token

      // Item 3: iOS 1.2.2 also exposes the backend token exchange code as
      // TSIdoServiceResponse.code alongside the completion token. Android's
      // TSIdoServiceResponse has no `code` property at NATIVE_SDK_VERSION, so the key is
      // omitted from the response map rather than sent as null. Logged once per plugin
      // instance - a journey can complete repeatedly and this is not a per-event error.
      if (!loggedMissingResponseCode) {
        loggedMissingResponseCode = true
        logNotImplementedOnAndroid("TSIdoServiceResponse.code")
      }
    }
    
    // Add error data if available
    response.errorData?.let { errorData ->
      responseDict["errorData"] = hashMapOf<String, Any>(
        "errorCode" to errorData.errorCode.dartCode,
        "errorMessage" to errorData.errorMessage
      )
    }
    
    val resultMap = hashMapOf<String, Any>(
      "success" to true,
      "response" to responseDict
    )
    eventSink?.success(resultMap)
  }

  private fun handleSetLoggingEnabled(call: MethodCall, result: Result) {
    val arguments = call.arguments as? Map<String, Any>
    val enabled = arguments?.get("enabled") as? Boolean

    if (enabled == null) {
      result.error(
        IdentityOrchestrationPluginError.InvalidArguments.rawValue,
        "Missing enabled parameter - must be true or false",
        null
      )
      return
    }

    Log.d(TAG, "TSIdo.setLoggingEnabled $enabled")

    TSIdo.setLoggingEnabled(enabled)
    result.success(true)
  }

  // Utils

  private fun convertResponseOptionId(rawResponseOptionId: String): TSIdoClientResponseOptionType {
    return when (rawResponseOptionId) {
      "clientInput" -> TSIdoClientResponseOptionType.ClientInput
      "cancel" -> TSIdoClientResponseOptionType.Cancel
      "fail" -> TSIdoClientResponseOptionType.Fail
      "resend" -> TSIdoClientResponseOptionType.Resend
      else -> TSIdoClientResponseOptionType.Custom
    }
  }

  private fun handleGenerateDebugPin(call: MethodCall, result: Result) {
    TSIdo.generateDebugPin(object : TSIdoCallback<String> {
      override fun idoSuccess(pinResults: String) {
        result.success(pinResults)
      }

      override fun idoError(error: TSIdoSdkError) {
        result.error(
          "GENERATE_DEBUG_PIN_ERROR",
          "Failed to generate debug pin",
          error.errorMessage
        )
      }
      
      // NOTE: TSIdoCallback<String> doesn't support idoInstruction method
      // Instructions support for generateDebugPin would require a different callback type
    })
  }

  // EventChannel.StreamHandler methods
  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  private fun convertStartJourneyOptions(rawOptions: Map<String, Any>?):  TSIdoStartJourneyOptions? {
    if (rawOptions == null) return null

    val additionalParams = rawOptions["additionalParams"] as? Map<String, Any>?
    val encryptionMode = parseEncryptionMode(rawOptions["encrypted"] as? Boolean)

    val options =  TSIdoStartJourneyOptions(
      additionalParams = additionalParams,
      flowId = rawOptions["flowId"] as? String,
      encryptionMode = encryptionMode,
      drsSessionToken = parseDrsSessionToken(rawOptions)
    )

    return options
  }

  private fun parseEncryptionMode(encrypted: Boolean?): TSIdoEncryptionMode {
    return when (encrypted) {
      true -> TSIdoEncryptionMode.Full
      false, null -> TSIdoEncryptionMode.None
    }
  }

  // Helper function to convert JSON objects to Flutter-compatible types
  private fun convertJsonToFlutterCompatible(value: Any?): Any {
    return when (value) {
      is JSONObject -> {
        val map = hashMapOf<String, Any>()
        value.keys().forEach { key ->
          val convertedValue = convertJsonToFlutterCompatible(value.get(key))
          map[key] = convertedValue
        }
        map
      }
      is JSONArray -> {
        val list = arrayListOf<Any>()
        for (i in 0 until value.length()) {
          list.add(convertJsonToFlutterCompatible(value.get(i)))
        }
        list
      }
      null -> hashMapOf<String, Any>() // Convert null to empty map to avoid nullable issues
      else -> value
    }
  }
}
