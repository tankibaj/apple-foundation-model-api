import Foundation

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
