import Foundation
import Network

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
logLine("afm-api server listening on http://\(cfg.host):\(cfg.port)")
logLine("API version: \(cfg.apiVersion)")
logLine("Model id: \(cfg.modelName)")
RunLoop.main.run()
