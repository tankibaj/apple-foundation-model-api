import Foundation
import Darwin

final class RuntimeLogger {
    static let shared = RuntimeLogger()

    private let logFilePath: String?
    private let logMaxBytes: Int64
    private let logMaxFiles: Int
    private let stdoutIsTTY: Bool
    private let queue = DispatchQueue(label: "afm-api.runtime-logger", qos: .utility)
    private let fm = FileManager.default

    private var fileHandle: FileHandle?
    private var fileSize: Int64 = 0

    private init() {
        self.logFilePath = ProcessInfo.processInfo.environment["AFM_API_LOG_FILE"]
        self.logMaxBytes = Int64(ProcessInfo.processInfo.environment["AFM_API_LOG_MAX_BYTES"] ?? "") ?? 10 * 1024 * 1024
        let logMaxFilesRaw = Int(ProcessInfo.processInfo.environment["AFM_API_LOG_MAX_FILES"] ?? "") ?? 3
        self.logMaxFiles = max(1, logMaxFilesRaw)
        self.stdoutIsTTY = isatty(fileno(stdout)) == 1

        guard let path = logFilePath, !path.isEmpty else { return }
        openHandle(path: path)
    }

    deinit {
        try? fileHandle?.close()
    }

    func log(_ message: String) {
        guard stdoutIsTTY || (logFilePath?.isEmpty == false) else { return }
        queue.async { [self] in
            if stdoutIsTTY {
                fputs(message + "\n", stdout)
            }
            guard let path = logFilePath, !path.isEmpty else { return }
            guard let data = (message + "\n").data(using: .utf8) else { return }

            rotateIfNeeded(path: path, incomingBytes: Int64(data.count))
            if fileHandle == nil {
                openHandle(path: path)
            }
            guard let handle = fileHandle else { return }

            do {
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
                fileSize += Int64(data.count)
            } catch {
                try? handle.close()
                fileHandle = nil
            }
        }
    }

    private func openHandle(path: String) {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent().path
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }

        if let attrs = try? fm.attributesOfItem(atPath: path),
           let sizeNum = attrs[.size] as? NSNumber {
            fileSize = sizeNum.int64Value
        } else {
            fileSize = 0
        }

        do {
            fileHandle = try FileHandle(forWritingTo: url)
            _ = try fileHandle?.seekToEnd()
        } catch {
            fileHandle = nil
        }
    }

    private func rotateIfNeeded(path: String, incomingBytes: Int64) {
        guard logMaxBytes > 0 else { return }
        guard fileSize + incomingBytes >= logMaxBytes else { return }

        try? fileHandle?.close()
        fileHandle = nil

        for idx in stride(from: logMaxFiles - 1, through: 0, by: -1) {
            let src = idx == 0 ? path : "\(path).\(idx)"
            let dst = "\(path).\(idx + 1)"

            guard fm.fileExists(atPath: src) else { continue }
            if fm.fileExists(atPath: dst) {
                try? fm.removeItem(atPath: dst)
            }
            try? fm.moveItem(atPath: src, toPath: dst)
        }

        fm.createFile(atPath: path, contents: nil)
        fileSize = 0
        openHandle(path: path)
    }
}

func logLine(_ message: String) {
    RuntimeLogger.shared.log(message)
}
