import Foundation

func encodeJSONObjectString(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value),
          let text = String(data: data, encoding: .utf8) else {
        return nil
    }
    return text
}

func makeToolCall(name: String, argsObj: Any) -> ToolCall {
    let argsString: String
    if let s = argsObj as? String {
        if let data = s.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let encoded = encodeJSONObjectString(json) {
            argsString = encoded
        } else {
            argsString = "{\"value\":\(String(describing: s).debugDescription)}"
        }
    } else if let encoded = encodeJSONObjectString(argsObj) {
        argsString = encoded
    } else {
        argsString = "{\"value\":\(String(describing: argsObj).debugDescription)}"
    }
    return ToolCall(
        id: "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))",
        type: "function",
        function: ToolCallFunction(name: name, arguments: argsString)
    )
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
