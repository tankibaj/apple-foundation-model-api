import Foundation

func jsonData(_ obj: Any) -> Data {
    guard JSONSerialization.isValidJSONObject(obj) else {
        return Data("{\"error\":{\"message\":\"internal serialization error\"}}".utf8)
    }
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
        return data
    }
    return Data("{\"error\":{\"message\":\"internal serialization error\"}}".utf8)
}

func httpResponse(status: Int, body: Data, contentType: String = "application/json") -> Data {
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 400: reason = "Bad Request"
    case 404: reason = "Not Found"
    case 500: reason = "Internal Server Error"
    default: reason = "OK"
    }

    var head = "HTTP/1.1 \(status) \(reason)\r\n"
    head += "Content-Type: \(contentType)\r\n"
    head += "Content-Length: \(body.count)\r\n"
    head += "Connection: close\r\n\r\n"
    var data = Data(head.utf8)
    data.append(body)
    return data
}
