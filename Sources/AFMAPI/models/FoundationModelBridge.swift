import Foundation
import FoundationModels

enum BridgeRuntimeError: Error {
    case unsupportedOS
}

func runModel(input: BridgeInput) async throws -> BridgeOutput {
    guard #available(macOS 26.0, *) else {
        throw BridgeRuntimeError.unsupportedOS
    }

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
                if let textContent = encodeJSONObjectString(contentObj) {
                    return BridgeOutput(content: textContent, tool_calls: nil, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
                }
                return BridgeOutput(content: String(describing: contentObj), tool_calls: nil, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
            }
        }
    }

    return BridgeOutput(content: text, tool_calls: nil, prompt_tokens: 0, completion_tokens: 0, total_tokens: 0)
}
