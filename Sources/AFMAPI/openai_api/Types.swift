import Foundation

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

struct ChatCompletionsRequest: Codable {
    let model: String?
    let messages: [ChatMessage]
    let tools: [OpenAITool]?
    let tool_choice: ToolChoice?
    let temperature: Double?
    let max_tokens: Int?
    let stream: Bool?
}
