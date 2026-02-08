import Foundation
import Network

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
        _ = lock.sync {
            handlers.removeValue(forKey: ObjectIdentifier(handler))
        }
    }
}
