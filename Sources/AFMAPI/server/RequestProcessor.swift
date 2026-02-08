import Foundation

final class RequestProcessor {
    let cfg: AppConfig

    init(cfg: AppConfig) {
        self.cfg = cfg
    }

    func handle(method: String, path: String, body: Data) async -> Data {
        let started = Date()
        func finish(_ status: Int, _ payload: Any) -> Data {
            let ms = Int(Date().timeIntervalSince(started) * 1000.0)
            logLine("[\(status)] \(method) \(path) \(ms)ms")
            return httpResponse(status: status, body: jsonData(payload))
        }

        if method == "GET" && path == "/healthz" {
            return finish(200, ["ok": true])
        }

        let apiBase = apiBasePath(cfg.apiVersion)

        if method == "GET" && path == "\(apiBase)" {
            return finish(200, [
                "object": "api.version",
                "version": cfg.apiVersion
            ])
        }

        if method == "GET" && path == "\(apiBase)/health" {
            do {
                _ = try await runModel(input: BridgeInput(
                    model: cfg.modelName,
                    messages: [ChatMessage(role: "user", content: "ping", name: nil, tool_calls: nil)],
                    tools: [],
                    tool_choice: .none,
                    temperature: 0.0,
                    max_output_tokens: 8
                ))
                return finish(200, [
                    "ok": true,
                    "check": "model",
                    "model": cfg.modelName
                ])
            } catch {
                return finish(500, [
                    "ok": false,
                    "check": "model",
                    "model": cfg.modelName,
                    "error": String(describing: error)
                ])
            }
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
            return finish(200, payload)
        }

        guard method == "POST" && path == "\(apiBase)/chat/completions" else {
            return finish(404, ["error": ["message": "Not found", "type": "invalid_request_error"]])
        }

        let decoder = JSONDecoder()
        let req: ChatCompletionsRequest
        do {
            req = try decoder.decode(ChatCompletionsRequest.self, from: body)
        } catch {
            return finish(400, ["error": ["message": "Invalid JSON", "type": "invalid_request_error"]])
        }

        if req.stream == true {
            return finish(400, ["error": ["message": "stream=true is not implemented yet", "type": "invalid_request_error"]])
        }

        if req.messages.isEmpty {
            return finish(400, ["error": ["message": "messages must be a non-empty array", "type": "invalid_request_error"]])
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

            return finish(200, payload)
        } catch {
            return finish(500, ["error": ["message": "Bridge process failed: \(error)", "type": "server_error"]])
        }
    }
}
