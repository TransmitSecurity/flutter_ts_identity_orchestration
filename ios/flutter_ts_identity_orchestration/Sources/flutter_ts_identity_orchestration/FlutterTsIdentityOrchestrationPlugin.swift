import Flutter
import UIKit
import IdentityOrchestration

enum IdentityOrchestrationPluginError: String {
    case invalidArguments
    case sdkInitError
    case startJourneyError
    case startMobileApproveError
    case submitResponseError
    case generateDebugPINError
    case setPushTokenError
    case modularIdvHookError
}

public class FlutterTsIdentityOrchestrationPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, TSIdoDelegate {
    
    private var eventSink: FlutterEventSink?

    /// Owns modular IDV hook state: which hooks Dart enabled, and the contexts of steps currently
    /// suspended in one.
    ///
    /// Events are dispatched to the main queue before reaching the sink. Unlike Android, whose SDK
    /// routes both hooks through `runWhenResumed`, this platform invokes `onBefore` inline from the
    /// IDO controller and `onAfter` from the IDV SDK's completion — neither is guaranteed to be the
    /// main thread, and a `FlutterEventSink` must be called there.
    private lazy var modularIDVHookBridge = ModularIDVHookBridge { [weak self] event in
        DispatchQueue.main.async { self?.eventSink?(event) }
    }

    /// Modular IDV UI handler. Held for the plugin's lifetime rather than created per call, so the
    /// same instance is re-registered before every journey — see `registerModularIDVUIHandler()`.
    private lazy var modularIDVUIHandler = ModularIDVUIHandler(hookBridge: modularIDVHookBridge)

    /// Registers the Modular IDV UI handler immediately before starting a journey.
    ///
    /// Called before every journey start rather than once at init, matching both native demo apps.
    /// On Android this ordering is load-bearing: `setUIHandler` also clears the cached
    /// `ModularIDVController`, which holds the `start_token` reused across the document and selfie
    /// steps of a single journey — so registering mid-journey would discard it.
    ///
    /// Failure is logged, not surfaced: `setUIHandler` throws only when the SDK is not initialized,
    /// and in that case the subsequent `startJourney` reports the real error. Failing the journey
    /// start here would turn a Modular IDV setup problem into an unrelated error for every caller,
    /// including the majority whose journeys never reach an acquisition step.
    ///
    /// Pending hooks are dropped here rather than at journey end, because a journey has no single
    /// end: it can complete, error, or simply be abandoned. Starting the next one is the only point
    /// where the previous journey's suspended steps are provably dead.
    private func registerModularIDVUIHandler() {
        modularIDVHookBridge.reset()

        do {
            try TSIdo.setUIHandler(modularIDVUIHandler)
        } catch {
            NSLog("[flutter_ts_identity_orchestration] Modular IDV UI handler not registered: \(error). Document and selfie acquisition steps will be delivered as unhandled journey steps.")
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_ts_identity_orchestration", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_ts_identity_orchestration_events", binaryMessenger: registrar.messenger())
        let instance = FlutterTsIdentityOrchestrationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initializeSDK":
            handleInitializeSDK(call: call, result: result)
        case "initialize":
            handleInitialize(call: call, result: result)
        case "startJourney":
            handleStartJourney(call: call, result: result)
        case "submitClientResponse":
            handleSubmitClientResponse(call: call, result: result)
        case "generateDebugPin":
            handleGenerateDebugPin(call: call, result: result)
        case "startMobileApproveJourney":
            handleStartMobileApproveJourney(call: call, result: result)
        case "setLoggingEnabled":
            handleSetLoggingEnabled(call: call, result: result)
        case "setPushToken":
            handleSetPushToken(call: call, result: result)
        case "setModularIdvHooks":
            handleSetModularIdvHooks(call: call, result: result)
        case "resumeModularIdvStep":
            handleResumeModularIdvStep(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleInitializeSDK(call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let arguments = call.arguments as? [String: Any]
            let configurationFile = arguments?["configurationFile"] as? String
            
            if let configurationFile = configurationFile, !configurationFile.isEmpty {
                let configuration = TSIdoConfiguration(configurationFileName: configurationFile)
                try? TSIdo.initializeSDK(configuration: configuration)
            } else {
                try? TSIdo.initializeSDK()
            }
            
            TSIdo.delegate = self
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.sdkInitError.rawValue,
                message: "Error initializing the SDK",
                details: error.localizedDescription
            ))
        }
    }
    
    private func handleInitialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Error initializing the SDK",
                details: nil
            ))
            return
        }
        
        let clientId = arguments["clientId"] as? String
        let options = arguments["options"] as? [String: Any]
        
        guard let clientId = clientId, !clientId.isEmpty else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Error initializing the SDK",
                details: "Invalid client identifier provided"
            ))
            return
        }
        
        let serverPath = options?["serverPath"] as? String ?? "https://api.transmitsecurity.io"
        let resource = options?["resource"] as? String
        let pollingTimeout = options?["pollingTimeout"] as? Int
        let locale = options?["locale"] as? String ?? "en"
        // Defaults to false when absent or not a Bool, matching the native SDK default.
        let collectRiskData = options?["collectRiskData"] as? Bool ?? false

        let initOptions = TSIdoInitJourneyOptions(
            serverPath: serverPath,
            resource: resource,
            pollingTimeout: pollingTimeout,
            locale: locale,
            collectRiskData: collectRiskData
        )
        
        do {
            try? TSIdo.initialize(clientId: clientId, options: initOptions)
            TSIdo.delegate = self
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.sdkInitError.rawValue,
                message: "Error initializing the SDK",
                details: error.localizedDescription
            ))
        }
    }
    
    private func handleStartJourney(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Invalid starting journey. No arguments provided",
                details: nil
            ))
            return
        }
        
        guard let journeyId = arguments["journeyId"] as? String, !journeyId.isEmpty else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Error starting journey",
                details: "Invalid journey ID provided"
            ))
            return
        }
        
        let options = arguments["options"] as? [String: Any]
        let additionalParams = options?["additionalParams"] as? [String: Any]
        let flowId = options?["flowId"] as? String
        let encryptionMode = (options?["encryptionMode"] as? Bool) ?? false
        // The native SDK appends the DRS header only for a non-empty token, so
        // normalize an empty or whitespace-only string to nil rather than forwarding it.
        let drsSessionToken = normalizedDrsSessionToken(from: options)

        let journeyStartOptions = TSIdoStartJourneyOptions(
            additionalParams: additionalParams,
            flowId: flowId,
            drsSessionToken: drsSessionToken,
            encryptionMode: encryptionMode ? .full: .none
        )
        
        do {
            registerModularIDVUIHandler()
            try TSIdo.startJourney(journeyId: journeyId, options: journeyStartOptions)
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.startJourneyError.rawValue,
                message: "Error starting journey",
                details: NativeErrorPayload.details(for: error)
            ))
        }
    }
    
    private func handleSubmitClientResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Invalid submitClientResponse. No arguments provided",
                details: nil
            ))
            return
        }
        
        guard let clientResponseOptionId = arguments["responseId"] as? String, !clientResponseOptionId.isEmpty else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Error submitting client response",
                details: "Invalid response id provided"
            ))
            return
        }
                                
        do {
            
            let actionId = convertResponseOptionId(clientResponseOptionId)
            
            try TSIdo.submitClientResponse(
                clientResponseOptionId: actionId,
                data: arguments["data"] as? [String: Any],
            ) { [weak self] instructions in
                self?.handleInstructions(instructions)
            }
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.submitResponseError.rawValue,
                message: "Error during client response submission",
                details: NativeErrorPayload.details(for: error)
            ))
        }
    }
    
    private func handleInstructions(_ instructions: Any?) {
        var instructionDict: [String: Any] = [:]
        
        // Convert instructions to Flutter-compatible format
        if let instructions = instructions {
            instructionDict = convertToFlutterCompatible(instructions)
        }
        
        let instructionEvent: [String: Any] = [
            "type": "instructions",
            "instructions": instructionDict
        ]
        
        eventSink?(instructionEvent)
    }
    
    private func convertToFlutterCompatible(_ value: Any) -> [String: Any] {
        var result: [String: Any] = [:]
        
        // Handle TSIdoInstruction specifically
        if let instruction = value as? TSIdoInstruction {
            result["type"] = String(describing: instruction.type)
            result["stepId"] = instruction.stepId
            
            // Convert data safely - instruction.data is not optional
            result["data"] = convertDataToFlutterCompatible(instruction.data)
            
            return result
        }
        
        // Handle dictionaries
        if let dict = value as? [String: Any] {
            for (key, val) in dict {
                result[key] = convertValueToFlutterCompatible(val)
            }
            return result
        }
        
        // Handle arrays
        if let array = value as? [Any] {
            result["items"] = array.map { convertValueToFlutterCompatible($0) }
            return result
        }
        
        // Handle other types by converting to string
        result["data"] = String(describing: value)
        return result
    }
    
    private func convertDataToFlutterCompatible(_ data: [String: Any]) -> [String: Any] {
        var flutterData: [String: Any] = [:]
        
        for (key, value) in data {
            flutterData[key] = convertValueToFlutterCompatible(value)
        }
        
        return flutterData
    }
    
    private func convertValueToFlutterCompatible(_ value: Any) -> Any {
        // Handle basic Flutter-supported types
        if value is String || value is Int || value is Double || value is Bool {
            return value
        }
        
        // Handle NSNumber (common in iOS)
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        
        // Handle arrays recursively
        if let array = value as? [Any] {
            return array.map { convertValueToFlutterCompatible($0) }
        }
        
        // Handle dictionaries recursively
        if let dict = value as? [String: Any] {
            var flutterDict: [String: Any] = [:]
            for (key, val) in dict {
                flutterDict[key] = convertValueToFlutterCompatible(val)
            }
            return flutterDict
        }
        
        // For any other type that Flutter can't serialize, convert to string
        return String(describing: value)
    }
    
    private func handleGenerateDebugPin(call: FlutterMethodCall, result: @escaping FlutterResult) {
        func respondWithError(_ error: Error) {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.generateDebugPINError.rawValue,
                message: "Error during generateDebugPin",
                details: error.localizedDescription
            ))
        }
        
        do {
            try TSIdo.generateDebugPin { pinResult in
                switch pinResult {
                case .success(let response):
                    result(response)
                case .failure(let error):
                    respondWithError(error)
                }
            }
        } catch {
            respondWithError(error)
        }
    }
    
    private func handleStartMobileApproveJourney(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Error starting mobile approve journey. Invalid arguments provided",
                details: nil
            ))
            return
        }
        
        guard let payload = arguments["payload"] as? [String: Any] else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Payload is required",
                details: nil
            ))
            return
        }
        
        let startJourneyOptions = arguments["startJourneyOptions"] as? [String: Any]
        
        do {
            registerModularIDVUIHandler()
            try TSIdo.startMobileApproveJourney(
                payload: payload,
                options: self.convertStartJourneyOptions(startJourneyOptions)
            )
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.startMobileApproveError.rawValue,
                message: "Failed to start mobile approve journey",
                details: NativeErrorPayload.details(for: error)
            ))
        }
    }
    
    private func handleSetLoggingEnabled(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let enabled = arguments["enabled"] as? Bool else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Missing enabled parameter - must be true or false",
                details: nil
            ))
            return
        }
        
        if enabled {
            TSIdo.setLogLevel(.debug)
        } else {
            TSIdo.setLogLevel(.off)
        }
        result(true)
    }
    
    private func handleSetPushToken(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let token = arguments["token"] as? String else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Invalid arguments for setPushToken",
                details: "Token parameter is required"
            ))
            return
        }
        
        do {
            try TSIdo.setPushToken(token)
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.setPushTokenError.rawValue,
                message: "Failed to set push token",
                details: error.localizedDescription
            ))
        }
    }
    
    // MARK: - Modular IDV hooks

    /// Enables or disables the modular IDV hooks. Both default to off.
    private func handleSetModularIdvHooks(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Error configuring modular IDV hooks. Invalid arguments provided",
                details: nil
            ))
            return
        }

        modularIDVHookBridge.setEnabled(
            onBefore: arguments["onBefore"] as? Bool ?? false,
            onAfter: arguments["onAfter"] as? Bool ?? false
        )
        result(true)
    }

    /// Resumes a suspended acquisition step, either along the SDK's default path or by submitting a
    /// client response that branches the journey.
    ///
    /// `responseId` is converted with the same `convertResponseOptionId` mapping
    /// `handleSubmitClientResponse` uses, so a hook response and a normal one behave identically
    /// for the same Dart id.
    private func handleResumeModularIdvStep(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let hookId = arguments["hookId"] as? String,
              !hookId.isEmpty else {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.invalidArguments.rawValue,
                message: "Hook id is required",
                details: nil
            ))
            return
        }

        let action: ModularIDVResume
        if let rawResponseId = arguments["responseId"] as? String, !rawResponseId.isEmpty {
            action = .submit(
                option: convertResponseOptionId(rawResponseId),
                data: arguments["data"] as? [String: Any]
            )
        } else {
            action = .proceed
        }

        switch modularIDVHookBridge.resume(hookId: hookId, action: action) {
        case .resumed:
            result(true)
        case .unknownHookId:
            result(FlutterError(
                code: IdentityOrchestrationPluginError.modularIdvHookError.rawValue,
                message: "No modular IDV step is waiting for this hook id",
                details: "It was already resumed, or a new journey was started since it was issued"
            ))
        case let .failed(error):
            result(FlutterError(
                code: IdentityOrchestrationPluginError.modularIdvHookError.rawValue,
                message: "Failed to resume modular IDV step",
                details: error.localizedDescription
            ))
        }
    }

    // MARK: - Helpers

    private func convertResponseOptionId(_ rawResponseOptionId: String) -> TSIdoClientResponseOptionType {
      switch rawResponseOptionId {
      case "clientInput": return .clientInput
      case "cancel": return .cancel
      case "fail": return .fail
      case "resend": return .resend
      default: return .custom(id: rawResponseOptionId)
      }
    }
    
    /// Reads `drsSessionToken` from a raw options map, trimming surrounding whitespace and
    /// treating an absent, non-String, empty, or whitespace-only value as nil.
    ///
    /// The native SDK appends the DRS header only for a non-empty token, so forwarding `""` would
    /// send an empty header rather than none. Extracted to one place because both journey-start
    /// paths need identical handling — they previously carried separate copies that drifted.
    private func normalizedDrsSessionToken(from options: [String: Any]?) -> String? {
        guard let token = options?["drsSessionToken"] as? String else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func convertStartJourneyOptions(_ rawOptions: [String: Any]?) -> TSIdoStartJourneyOptions? {
        guard let rawOptions = rawOptions else { return nil }
        
        let encryptionMode = rawOptions["encrypted"] as? Bool ?? false
        let drsSessionToken = normalizedDrsSessionToken(from: rawOptions)

        return TSIdoStartJourneyOptions(
          additionalParams: rawOptions["additionalParams"] as? [String : Any],
          flowId: rawOptions["flowId"] as? String,
          drsSessionToken: drsSessionToken,
          encryptionMode: encryptionMode ? .full : .none
        )
      }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    // MARK: - TSIdoDelegate
    
    public func TSIdoDidReceiveResult(_ result: Result<any TSIdoServiceResponse, TSIdoJourneyError>) {
        print("TSIdoDidReceiveResult: \(result)")
        
        switch result {
        case .success(let serviceResponse):
            var responseDict: [String: Any] = [:]
            
            if let data = serviceResponse.data {
                responseDict["data"] = data
            }
            
            if let journeyStepId = serviceResponse.journeyStepId {
                responseDict["journeyStepId"] = String(describing: journeyStepId)
            }
            
            if let clientResponseOptions = serviceResponse.clientResponseOptions {
                var optionsDict: [String: [String: Any]] = [:]
                for (key, option) in clientResponseOptions {
                    var optionDict: [String: Any] = [:]
                    optionDict["id"] = option.id
                    optionDict["label"] = option.label
                    optionDict["type"] = String(describing: option.type)
                    if let schema = option.schema {
                        optionDict["schema"] = schema
                    }
                    optionsDict[key] = optionDict
                }
                responseDict["clientResponseOptions"] = optionsDict
            }
            
            if let token = serviceResponse.token {
                responseDict["token"] = token
            }

            // Backend token exchange code, exposed by IDO iOS 1.2.2. Parsed from the
            // nested `data.code` field by the native SDK. Absent on Android at 1.0.34.
            if let code = serviceResponse.code {
                responseDict["code"] = code
            }
            
            if let errorData = serviceResponse.errorData {
                responseDict["errorData"] = [
                    "errorCode": NativeErrorPayload.code(for: errorData.errorCode),
                    "errorMessage": errorData.description
                ]
            }
            
            let resultMap: [String: Any] = [
                "success": true,
                "response": responseDict
            ]
            
            eventSink?(resultMap)
            
        case .failure(let error):
            // Modular IDV failures all arrive wrapped as TSIdoJourneyError.internalError(IdoError),
            // so without the mapping they would be indistinguishable from any other internal error.
            // NativeErrorPayload is the one place that derives a code, shared with the method-channel
            // error path so the two cannot drift; non-IDV errors keep their previous value.
            let errorCode = NativeErrorPayload.code(for: error)

            let resultMap: [String: Any] = [
                "success": false,
                "error": error.localizedDescription,
                "errorCode": errorCode
            ]

            eventSink?(resultMap)
        }
    }
}

extension Encodable {
    func toDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
