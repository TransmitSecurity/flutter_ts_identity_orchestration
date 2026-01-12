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
}

public class FlutterTsIdentityOrchestrationPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, TSIdoDelegate {
    
    private var eventSink: FlutterEventSink?
    
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
        
        let initOptions = TSIdoInitJourneyOptions(
            serverPath: serverPath,
            resource: resource,
            pollingTimeout: pollingTimeout,
            locale: locale
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
        
        let journeyStartOptions = TSIdoStartJourneyOptions(
            additionalParams: additionalParams,
            flowId: flowId,
            encryptionMode: encryptionMode ? .full: .none
        )
        
        do {
            try TSIdo.startJourney(journeyId: journeyId, options: journeyStartOptions)
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.startJourneyError.rawValue,
                message: "Error starting journey",
                details: error.localizedDescription
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
                details: error.localizedDescription
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
            try TSIdo.startMobileApproveJourney(
                payload: payload,
                options: self.convertStartJourneyOptions(startJourneyOptions)
            )
            result(true)
        } catch {
            result(FlutterError(
                code: IdentityOrchestrationPluginError.startMobileApproveError.rawValue,
                message: "Failed to start mobile approve journey",
                details: error.localizedDescription
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
    
    private func convertStartJourneyOptions(_ rawOptions: [String: Any]?) -> TSIdoStartJourneyOptions? {
        guard let rawOptions = rawOptions else { return nil }
        
        let encryptionMode = rawOptions["encrypted"] as? Bool ?? false
        
        return TSIdoStartJourneyOptions(
          additionalParams: rawOptions["additionalParams"] as? [String : Any],
          flowId: rawOptions["flowId"] as? String,
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
            
            if let errorData = serviceResponse.errorData {
                responseDict["errorData"] = [
                    "errorCode": String(describing: errorData.errorCode),
                    "errorMessage": errorData.description
                ]
            }
            
            let resultMap: [String: Any] = [
                "success": true,
                "response": responseDict
            ]
            
            eventSink?(resultMap)
            
        case .failure(let error):
            let resultMap: [String: Any] = [
                "success": false,
                "error": error.localizedDescription,
                "errorCode": String(describing: error)
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
