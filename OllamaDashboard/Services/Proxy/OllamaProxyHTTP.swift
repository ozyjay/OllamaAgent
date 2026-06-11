import Foundation
import Network

struct OllamaProxyHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

enum OllamaProxyError: LocalizedError {
    case invalidRequest
    case unsupportedChunkedRequest
    case invalidTargetURL

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "The proxy received an invalid HTTP request."
        case .unsupportedChunkedRequest: return "Chunked request bodies are not supported by this lightweight proxy."
        case .invalidTargetURL: return "The proxy target URL could not be built."
        }
    }
}

struct OllamaProxyForwardFailure: LocalizedError {
    let statusCode: Int?
    let underlyingDescription: String

    var errorDescription: String? {
        underlyingDescription
    }
}

enum OllamaProxyHTTPReader {
    static func readRequest(from connection: NWConnection) async throws -> OllamaProxyHTTPRequest {
        var buffer = Data()
        while !buffer.containsHTTPHeaderDelimiter {
            buffer.append(try await connection.receiveData(maximumLength: 64 * 1_024))
            guard buffer.count <= 1_024 * 1_024 else { throw OllamaProxyError.invalidRequest }
        }

        guard let headerRange = buffer.httpHeaderDelimiterRange,
              let headerText = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8)
        else {
            throw OllamaProxyError.invalidRequest
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw OllamaProxyError.invalidRequest }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { throw OllamaProxyError.invalidRequest }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        if headers["transfer-encoding"]?.localizedCaseInsensitiveContains("chunked") == true {
            throw OllamaProxyError.unsupportedChunkedRequest
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        var body = Data(buffer[headerRange.upperBound...])
        while body.count < contentLength {
            body.append(try await connection.receiveData(maximumLength: contentLength - body.count))
        }
        if body.count > contentLength {
            body = body.prefix(contentLength)
        }

        return OllamaProxyHTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
    }
}

enum OllamaProxyForwarder {
    static func forward(_ proxyRequest: OllamaProxyHTTPRequest, to target: URL, connection: NWConnection) async throws -> Int {
        var components = URLComponents(url: target, resolvingAgainstBaseURL: false)
        guard let pathComponents = URLComponents(string: proxyRequest.path) else {
            throw OllamaProxyError.invalidTargetURL
        }
        components?.path = pathComponents.path
        components?.percentEncodedQuery = pathComponents.percentEncodedQuery
        guard let url = components?.url else { throw OllamaProxyError.invalidTargetURL }

        var request = URLRequest(url: url)
        request.httpMethod = proxyRequest.method
        for (name, value) in proxyRequest.headers {
            guard !["host", "content-length", "connection", "accept-encoding"].contains(name) else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }
        if !proxyRequest.body.isEmpty {
            request.httpBody = proxyRequest.body
            request.setValue(String(proxyRequest.body.count), forHTTPHeaderField: "Content-Length")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
        let headers = (response as? HTTPURLResponse)?.allHeaderFields ?? [:]
        var responseHead = "HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))\r\n"
        for (rawName, rawValue) in headers {
            let name = String(describing: rawName)
            guard !["content-length", "transfer-encoding", "connection"].contains(name.lowercased()) else { continue }
            responseHead += "\(name): \(rawValue)\r\n"
        }
        responseHead += "Connection: close\r\n\r\n"
        do {
            try await connection.sendData(Data(responseHead.utf8))

            var chunk = Data()
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= 8_192 {
                    try await connection.sendData(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty {
                try await connection.sendData(chunk)
            }
        } catch {
            throw OllamaProxyForwardFailure(statusCode: statusCode, underlyingDescription: error.localizedDescription)
        }
        return statusCode
    }
}

private extension Data {
    var containsHTTPHeaderDelimiter: Bool {
        httpHeaderDelimiterRange != nil
    }

    var httpHeaderDelimiterRange: Range<Data.Index>? {
        range(of: Data("\r\n\r\n".utf8))
    }
}

extension NWConnection {
    func receiveData(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: OllamaProxyError.invalidRequest)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func sendData(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func sendHTTPStatus(_ statusCode: Int, body: String) async throws {
        let data = Data(body.utf8)
        let head = """
        HTTP/1.1 \(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode))\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r

        """
        try await sendData(Data(head.utf8) + data)
    }

    func sendHTTPResponse(_ response: PromptGuardrailHTTPResponse) async throws {
        let head = """
        HTTP/1.1 \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))\r
        Content-Type: \(response.contentType)\r
        Content-Length: \(response.body.count)\r
        Connection: close\r
        \r

        """
        try await sendData(Data(head.utf8) + response.body)
    }
}
