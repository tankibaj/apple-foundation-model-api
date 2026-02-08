import Foundation
import Darwin

let logFilePath = ProcessInfo.processInfo.environment["AFM_API_LOG_FILE"]
let logFileLock = NSLock()
let stdoutIsTTY = isatty(fileno(stdout)) == 1

func logLine(_ message: String) {
    if stdoutIsTTY {
        print(message)
    }
    guard let path = logFilePath, !path.isEmpty else { return }
    logFileLock.lock()
    defer { logFileLock.unlock() }
    let line = message + "\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: path) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    } else {
        FileManager.default.createFile(atPath: path, contents: data)
    }
}
