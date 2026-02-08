#!/usr/bin/env swift

import Foundation
import FoundationModels
import Network

struct BridgeInput: Codable {
    let model: String
    let messages: [ChatMessage]
    let tools: [OpenAITool]
    let tool_choice: ToolChoice
    let temperature: Double
    let max_output_tokens: Int
}

struct ChatMessage: Codable {
    let role: String
    let content: String?
    let name: String?
    let tool_calls: [ToolCall]?
}

struct OpenAITool: Codable {
    let type: String
    let function: ToolSpec
}

struct ToolSpec: Codable {
    let name: String
    let description: String?
    let parameters: JSONValue?
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: ToolCallFunction
}

struct ToolCallFunction: Codable {
    let name: String
    let arguments: String
}

enum ToolChoice: Codable {
    case auto
    case none
    case named(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            switch s {
            case "auto": self = .auto
            case "none": self = .none
            default: self = .named(s)
            }
            return
        }
        let obj = try c.decode([String: JSONValue].self)
        if case let .string(name)? = obj["name"] {
            self = .named(name)
        } else if case let .object(fn)? = obj["function"], case let .string(name)? = fn["name"] {
            self = .named(name)
        } else {
            self = .auto
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .auto: try c.encode("auto")
        case .none: try c.encode("none")
        case .named(let name): try c.encode(["name": name])
        }
    }
}

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

struct BridgeOutput: Codable {
    let content: String?
    let tool_calls: [ToolCall]?
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

func makeToolCall(name: String, argsObj: Any) -> ToolCall {
    let argsData = (try? JSONSerialization.data(withJSONObject: argsObj)) ?? Data("{}".utf8)
    let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
    return ToolCall(
        id: "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
        type: "function",
        function: ToolCallFunction(name: name, arguments: argsString)
    )
}

struct ChatCompletionsRequest: Codable {
    let model: String?
    let messages: [ChatMessage]
    let tools: [OpenAITool]?
    let tool_choice: ToolChoice?
    let temperature: Double?
    let max_tokens: Int?
    let stream: Bool?
}

struct AppConfig {
    let host: String
    let port: UInt16
    let modelName: String
    let apiVersion: String
}

func parseArg(_ name: String, default value: String) -> String {
    let args = CommandLine.arguments
    guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return value }
    return args[idx + 1]
}

func latestAPIVersion() -> String {
    return "v1"
}

func normalizeAPIVersion(_ version: String) -> String {
    let v = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if v == "latest" || v.isEmpty {
        return latestAPIVersion()
    }
    if v.hasPrefix("v") {
        return version
    }
    return "v\(version)"
}

func parseConfig() -> AppConfig {
    let host = parseArg("--host", default: "127.0.0.1")
    let portStr = parseArg("--port", default: "8000")
    let modelName = parseArg("--model-name", default: "apple-foundation-model")
    let apiVersion = normalizeAPIVersion(parseArg("--api-version", default: latestAPIVersion()))
    let port = UInt16(portStr) ?? 8000
    return AppConfig(host: host, port: port, modelName: modelName, apiVersion: apiVersion)
}

func apiBasePath(_ version: String) -> String {
    return "/\(version)"
}

func normalizeConversation(_ messages: [ChatMessage]) -> String {
    var lines: [String] = []
    for m in messages {
        let text = m.content ?? ""
        lines.append("[\(m.role)] \(text)")
    }
    return lines.joined(separator: "\n")
}

func toolsPromptBlock(_ tools: [OpenAITool], toolChoice: ToolChoice) -> String {
    guard !tools.isEmpty else {
        return "You have no tools. Answer directly with plain text only."
    }

    let toolsJSONData = try? JSONEncoder().encode(tools)
    let toolsJSON = String(data: toolsJSONData ?? Data("[]".utf8), encoding: .utf8) ?? "[]"

    var choiceLine = "Tool choice: auto."
    switch toolChoice {
    case .auto:
        choiceLine = "Tool choice: auto."
    case .none:
        choiceLine = "Tool choice: none. Never call a tool."
    case .named(let name):
        choiceLine = "Tool choice: required tool is \(name)."
    }

    return """
You may call tools. Available tools (OpenAI schema JSON):
\(toolsJSON)
\(choiceLine)

Respond in STRICT JSON using exactly one of these formats:
1) {"type":"final","content":"<assistant text>"}
2) {"type":"tool_calls","tool_calls":[{"name":"<tool_name>","arguments":{...}}]}

Rules:
- Emit valid JSON only, no markdown fences.
- If any tool is needed, choose type=tool_calls.
- If tool_choice is none, choose type=final.
"""
}

func normalizeJSONTextCandidate(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }

    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= 3 else { return trimmed }
    guard lines.first?.hasPrefix("```") == true, lines.last == "```" else { return trimmed }

    let body = lines.dropFirst().dropLast().joined(separator: "\n")
    return String(body).trimmingCharacters(in: .whitespacesAndNewlines)
}

func runModel(input: BridgeInput) async throws -> BridgeOutput {
    let session = LanguageModelSession(model: .default)

    let prompt = """
You are a compatibility layer for OpenAI chat completions.
\(toolsPromptBlock(input.tools, toolChoice: input.tool_choice))

Conversation:
\(normalizeConversation(input.messages))
"""

    let response = try await session.respond(to: prompt)
    let text = response.content
    let normalized = normalizeJSONTextCandidate(text)

    if let data = normalized.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let type = parsed["type"] as? String {
        if type == "tool_calls", let tc = parsed["tool_calls"] as? [[String: Any]] {
            let mapped: [ToolCall] = tc.compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                let argsObj = entry["arguments"] ?? [:]
                return makeToolCall(name: name, argsObj: argsObj)
            }

            if !mapped.isEmpty {
                return BridgeOutput(content: nil, tool_calls: mapped, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
            }
        }

        if type == "final" {
            if case let .named(requiredName) = input.tool_choice {
                let argsObj = parsed["content"] ?? [:]
                let tc = makeToolCall(name: requiredName, argsObj: argsObj)
                return BridgeOutput(content: nil, tool_calls: [tc], prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
            }
            if let content = parsed["content"] as? String {
                return BridgeOutput(content: content, tool_calls: nil, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
            }
            if let contentObj = parsed["content"] {
                if let data = try? JSONSerialization.data(withJSONObject: contentObj),
                   let textContent = String(data: data, encoding: .utf8) {
                    return BridgeOutput(content: textContent, tool_calls: nil, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
                }
            }
        }
    }

    return BridgeOutput(content: text, tool_calls: nil, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
}

func jsonData(_ obj: Any) -> Data {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
        return data
    }
    return Data("{\"error\":{\"message\":\"internal serialization error\"}}".utf8)
}

func httpResponse(status: Int, body: Data, contentType: String = "application/json") -> Data {
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 400: reason = "Bad Request"
    case 404: reason = "Not Found"
    case 500: reason = "Internal Server Error"
    default: reason = "OK"
    }

    var head = "HTTP/1.1 \(status) \(reason)\r\n"
    head += "Content-Type: \(contentType)\r\n"
    head += "Content-Length: \(body.count)\r\n"
    head += "Connection: close\r\n\r\n"
    var data = Data(head.utf8)
    data.append(body)
    return data
}

final class RequestProcessor {
    let cfg: AppConfig

    init(cfg: AppConfig) {
        self.cfg = cfg
    }

    func handle(method: String, path: String, body: Data) async -> Data {
        if method == "GET" && path == "/healthz" {
            return httpResponse(status: 200, body: jsonData(["ok": true]))
        }

        let apiBase = apiBasePath(cfg.apiVersion)

        if method == "GET" && path == "\(apiBase)" {
            return httpResponse(status: 200, body: jsonData([
                "object": "api.version",
                "version": cfg.apiVersion
            ]))
        }

        if method == "GET" && path == "\(apiBase)/models" {
            let payload: [String: Any] = [
                "object": "list",
                "data": [[
                    "id": cfg.modelName,
                    "object": "model",
                    "created": 0,
                    "owned_by": "apple"
                ]]
            ]
            return httpResponse(status: 200, body: jsonData(payload))
        }

        guard method == "POST" && path == "\(apiBase)/chat/completions" else {
            return httpResponse(status: 404, body: jsonData(["error": ["message": "Not found", "type": "invalid_request_error"]]))
        }

        let decoder = JSONDecoder()
        let req: ChatCompletionsRequest
        do {
            req = try decoder.decode(ChatCompletionsRequest.self, from: body)
        } catch {
            return httpResponse(status: 400, body: jsonData(["error": ["message": "Invalid JSON", "type": "invalid_request_error"]]))
        }

        if req.stream == true {
            return httpResponse(status: 400, body: jsonData(["error": ["message": "stream=true is not implemented yet", "type": "invalid_request_error"]]))
        }

        if req.messages.isEmpty {
            return httpResponse(status: 400, body: jsonData(["error": ["message": "messages must be a non-empty array", "type": "invalid_request_error"]]))
        }

        let bridgeInput = BridgeInput(
            model: req.model ?? cfg.modelName,
            messages: req.messages,
            tools: req.tools ?? [],
            tool_choice: req.tool_choice ?? .auto,
            temperature: req.temperature ?? 0.7,
            max_output_tokens: req.max_tokens ?? 1024
        )

        do {
            let bridgeOutput = try await runModel(input: bridgeInput)
            let completionId = "chatcmpl_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let created = Int(Date().timeIntervalSince1970)

            var message: [String: Any] = ["role": "assistant"]
            var finishReason = "stop"
            if let toolCalls = bridgeOutput.tool_calls {
                let toolCallObjs = toolCalls.map { tc in
                    [
                        "id": tc.id,
                        "type": tc.type,
                        "function": [
                            "name": tc.function.name,
                            "arguments": tc.function.arguments
                        ]
                    ]
                }
                message["tool_calls"] = toolCallObjs
                message["content"] = NSNull()
                finishReason = "tool_calls"
            } else {
                message["content"] = bridgeOutput.content ?? ""
            }

            let payload: [String: Any] = [
                "id": completionId,
                "object": "chat.completion",
                "created": created,
                "model": req.model ?? cfg.modelName,
                "choices": [[
                    "index": 0,
                    "message": message,
                    "finish_reason": finishReason
                ]],
                "usage": [
                    "prompt_tokens": bridgeOutput.prompt_tokens,
                    "completion_tokens": bridgeOutput.completion_tokens,
                    "total_tokens": bridgeOutput.total_tokens
                ]
            ]

            return httpResponse(status: 200, body: jsonData(payload))
        } catch {
            return httpResponse(status: 500, body: jsonData(["error": ["message": "Bridge process failed: \(error)", "type": "server_error"]]))
        }
    }
}

final class ConnectionHandler {
    private let connection: NWConnection
    private let processor: RequestProcessor
    private let onClose: (ConnectionHandler) -> Void
    private var buffer = Data()
    private var expectedBodyLength: Int?
    private var closed = false

    init(connection: NWConnection, processor: RequestProcessor, onClose: @escaping (ConnectionHandler) -> Void) {
        self.connection = connection
        self.processor = processor
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.receiveLoop()
            }
        }
        connection.start(queue: .global())
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if self.tryProcessIfComplete() {
                    return
                }
            }

            if isComplete || error != nil {
                self.close()
                return
            }

            self.receiveLoop()
        }
    }

    private func tryProcessIfComplete() -> Bool {
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return false
        }

        let headerData = buffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            send(status: 400, body: ["error": ["message": "Invalid request headers", "type": "invalid_request_error"]])
            return true
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            send(status: 400, body: ["error": ["message": "Invalid request line", "type": "invalid_request_error"]])
            return true
        }

        let reqParts = requestLine.split(separator: " ")
        guard reqParts.count >= 2 else {
            send(status: 400, body: ["error": ["message": "Invalid request line", "type": "invalid_request_error"]])
            return true
        }

        let method = String(reqParts[0])
        let path = String(reqParts[1])

        if expectedBodyLength == nil {
            expectedBodyLength = 0
            for line in lines.dropFirst() {
                if line.isEmpty { continue }
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 && parts[0].lowercased() == "content-length" {
                    expectedBodyLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
        }

        let bodyStart = headerRange.upperBound
        let bodyLen = buffer.count - bodyStart
        let needed = expectedBodyLength ?? 0
        guard bodyLen >= needed else {
            return false
        }

        let body = buffer.subdata(in: bodyStart..<(bodyStart + needed))

        var responseData = Data()
        let sem = DispatchSemaphore(value: 0)
        Task {
            responseData = await self.processor.handle(method: method, path: path, body: body)
            sem.signal()
        }
        sem.wait()
        self.connection.send(content: responseData, completion: .contentProcessed { _ in
            self.close()
        })

        return true
    }

    private func send(status: Int, body: [String: Any]) {
        let response = httpResponse(status: status, body: jsonData(body))
        connection.send(content: response, completion: .contentProcessed { _ in
            self.close()
        })
    }

    private func close() {
        if closed { return }
        closed = true
        connection.cancel()
        onClose(self)
    }
}

final class ConnectionRegistry {
    private static var handlers: [ObjectIdentifier: ConnectionHandler] = [:]
    private static let lock = DispatchQueue(label: "afm-api.connection.registry")

    static func add(_ handler: ConnectionHandler) {
        lock.sync {
            handlers[ObjectIdentifier(handler)] = handler
        }
    }

    static func remove(_ handler: ConnectionHandler) {
        lock.sync {
            handlers.removeValue(forKey: ObjectIdentifier(handler))
        }
    }
}

let cfg = parseConfig()
let processor = RequestProcessor(cfg: cfg)

let params = NWParameters.tcp

guard let listenerPort = NWEndpoint.Port(rawValue: cfg.port) else {
    fputs("Invalid port: \(cfg.port)\n", stderr)
    exit(2)
}

let listener = try NWListener(using: params, on: listenerPort)
listener.newConnectionHandler = { connection in
    let handler = ConnectionHandler(connection: connection, processor: processor) { h in
        ConnectionRegistry.remove(h)
    }
    ConnectionRegistry.add(handler)
    handler.start()
}
listener.start(queue: .main)
print("afm-api server listening on http://\(cfg.host):\(cfg.port)")
print("API version: \(cfg.apiVersion)")
print("Model id: \(cfg.modelName)")
RunLoop.main.run()
