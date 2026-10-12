import Foundation
import JavaScriptCore
import Flutter

/// Native iOS bridge leveraging Apple's built-in JavaScriptCore.framework.
/// Zero external C++ or CocoaPods dependencies required, preserving the unsigned IPA build.
public class JavaScriptCoreBridge: NSObject, FlutterPlugin {
    private static var contexts: [String: JSContext] = [:]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.jhomlala.animestream/javascriptcore",
            binaryMessenger: registrar.messenger()
        )
        let instance = JavaScriptCoreBridge()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        
        switch call.method {
        case "createContext":
            let contextId = args["contextId"] as? String ?? UUID().uuidString
            let context = JSContext() ?? JSContext(virtualMachine: JSVirtualMachine())
            
            guard let ctx = context else {
                result(FlutterError(code: "CONTEXT_CREATION_FAILED", message: "Failed to allocate JSContext", details: nil))
                return
            }
            
            // Setup sandboxed standard host APIs
            setupSandbox(context: ctx, contextId: contextId)
            
            JavaScriptCoreBridge.contexts[contextId] = ctx
            result(true)
            
        case "evaluateScript":
            guard let contextId = args["contextId"] as? String,
                  let script = args["script"] as? String,
                  let context = JavaScriptCoreBridge.contexts[contextId] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing contextId or script", details: nil))
                return
            }
            
            var exceptionMessage: String?
            context.exceptionHandler = { _, exception in
                exceptionMessage = exception?.toString()
            }
            
            if let jsValue = context.evaluateScript(script) {
                if let err = exceptionMessage {
                    result(FlutterError(code: "JS_EXCEPTION", message: err, details: nil))
                } else if jsValue.isUndefined || jsValue.isNull {
                    result(nil)
                } else if jsValue.isString {
                    result(jsValue.toString())
                } else if jsValue.isBoolean {
                    result(jsValue.toBool())
                } else if jsValue.isNumber {
                    result(jsValue.toNumber())
                } else {
                    // Object/Array: Serialize to JSON
                    if let jsonString = context.objectForKeyedSubscript("JSON")?
                        .objectForKeyedSubscript("stringify")?
                        .call(withArguments: [jsValue])?.toString() {
                        result(jsonString)
                    } else {
                        result(jsValue.toString())
                    }
                }
            } else {
                result(FlutterError(code: "EVAL_FAILED", message: exceptionMessage ?? "Evaluation returned nil", details: nil))
            }
            
        case "destroyContext":
            if let contextId = args["contextId"] as? String {
                JavaScriptCoreBridge.contexts.removeValue(forKey: contextId)
            }
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /// Binds safe host utilities into the JavaScript environment.
    private func setupSandbox(context: JSContext, contextId: String) {
        // Safe logging
        let console = JSValue(newObjectIn: context)
        let logBlock: @convention(block) (String) -> Void = { message in
            NSLog("[AnimestreamJS:\(contextId)] \(message)")
        }
        console?.setObject(logBlock, forKeyedSubscript: "log" as NSString)
        console?.setObject(logBlock, forKeyedSubscript: "warn" as NSString)
        console?.setObject(logBlock, forKeyedSubscript: "error" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
        
        // Base64 helper
        let atobBlock: @convention(block) (String) -> String = { encoded in
            guard let data = Data(base64Encoded: encoded),
                  let str = String(data: data, encoding: .utf8) else { return "" }
            return str
        }
        let btoaBlock: @convention(block) (String) -> String = { raw in
            return raw.data(using: .utf8)?.base64EncodedString() ?? ""
        }
        context.setObject(atobBlock, forKeyedSubscript: "atob" as NSString)
        context.setObject(btoaBlock, forKeyedSubscript: "btoa" as NSString)
        
        // Synchronous HTTP Fetch helper for scraping within execution timeout
        let httpGetBlock: @convention(block) (String, [String: String]?) -> String = { urlString, headers in
            guard let url = URL(string: urlString) else { return "{}" }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12.0
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Animestream/1.0", forHTTPHeaderField: "User-Agent")
            if let headers = headers {
                for (k, v) in headers {
                    request.setValue(v, forHTTPHeaderField: k)
                }
            }
            
            let semaphore = DispatchSemaphore(value: 0)
            var responseBody = ""
            
            let task = URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data, let text = String(data: data, encoding: .utf8) {
                    responseBody = text
                }
                semaphore.signal()
            }
            task.resume()
            _ = semaphore.wait(timeout: .now() + 12.0)
            return responseBody
        }
        
        let httpObj = JSValue(newObjectIn: context)
        httpObj?.setObject(httpGetBlock, forKeyedSubscript: "get" as NSString)
        context.setObject(httpObj, forKeyedSubscript: "http" as NSString)
    }
}
