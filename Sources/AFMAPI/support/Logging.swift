import Foundation
import Darwin

let logFilePath = ProcessInfo.processInfo.environment["AFM_API_LOG_FILE"]
let logMaxBytes = Int64(ProcessInfo.processInfo.environment["AFM_API_LOG_MAX_BYTES"] ?? "") ?? 10 * 1024 * 1024
let logMaxFilesRaw = Int(ProcessInfo.processInfo.environment["AFM_API_LOG_MAX_FILES"] ?? "") ?? 3
let logMaxFiles = max(1, logMaxFilesRaw)
let logFileLock = NSLock()
let stdoutIsTTY = isatty(fileno(stdout)) == 1

func rotateLogIfNeeded(path: String) {
    guard logMaxBytes > 0 else { return }
    guard FileManager.default.fileExists(atPath: path) else { return }

    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let sizeNum = attrs[.size] as? NSNumber else {
        return
    }

    let size = sizeNum.int64Value
    guard size >= logMaxBytes else { return }

    let fm = FileManager.default
    for idx in stride(from: logMaxFiles - 1, through: 0, by: -1) {
        let src = idx == 0 ? path : "\(path).\(idx)"
        let dst = "\(path).\(idx + 1)"

        guard fm.fileExists(atPath: src) else { continue }
        if fm.fileExists(atPath: dst) {
            try? fm.removeItem(atPath: dst)
        }
        try? fm.moveItem(atPath: src, toPath: dst)
    }
}

func logLine(_ message: String) {
    if stdoutIsTTY {
        print(message)
    }
    guard let path = logFilePath, !path.isEmpty else { return }
    logFileLock.lock()
    defer { logFileLock.unlock() }
    let line = message + "\n"
    guard let data = line.data(using: .utf8) else { return }
    rotateLogIfNeeded(path: path)
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
