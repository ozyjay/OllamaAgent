import Foundation

struct OllamaProxyRequest: Identifiable, Equatable {
    let id: UUID
    let model: String
    let path: String
    let startedAt: Date
}

struct OllamaProxyRequestMetadata: Equatable, CustomStringConvertible {
    let model: String?
    let path: String
    let bodyByteCount: Int
    let stream: Bool?
    let numCtx: Int?
    let numPredict: Int?
    let messageCount: Int?
    let promptCharacterCount: Int?

    var modelDisplayName: String {
        if let model {
            return model
        }
        if bodyByteCount == 0 {
            return "No request body"
        }
        if path == "/api/generate" || path == "/api/chat" || path == "/v1/chat/completions" {
            return "No model in request"
        }
        return "No model metadata"
    }

    var description: String {
        [
            "path=\(path)",
            model.map { "model=\($0)" },
            "bodyBytes=\(bodyByteCount)",
            stream.map { "stream=\($0)" },
            numCtx.map { "numCtx=\($0)" },
            numPredict.map { "numPredict=\($0)" },
            messageCount.map { "messages=\($0)" },
            promptCharacterCount.map { "promptChars=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

struct OllamaProxyRequestRecord: Identifiable, Equatable {
    let id: UUID
    let model: String
    let path: String
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let upstreamStatusCode: Int?
    let proxyError: String?
    let bodyByteCount: Int
    let stream: Bool?
    let numCtx: Int?
    let numPredict: Int?
    let messageCount: Int?
    let promptCharacterCount: Int?
    let estimatedTokenCount: Int?
    let guardrailOutcome: PromptGuardrailOutcome
    let guardrailReasons: [String]

    var isFailure: Bool {
        proxyError != nil || upstreamStatusCode.map { !(200..<300).contains($0) } == true
    }

    var isLikelyProviderTimeout: Bool {
        (55...75).contains(duration)
            && (proxyError != nil || upstreamStatusCode.map { (500...599).contains($0) } == true)
    }

    var statusText: String {
        if let upstreamStatusCode {
            return "\(upstreamStatusCode)"
        }
        if proxyError != nil {
            return "Proxy error"
        }
        return "Unknown"
    }
}

enum OllamaProxyRequestParser {
    static func modelName(from body: Data) -> String? {
        metadata(path: "", body: body).model
    }

    static func metadata(path: String, body: Data) -> OllamaProxyRequestMetadata {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return OllamaProxyRequestMetadata(
                model: nil,
                path: path,
                bodyByteCount: body.count,
                stream: nil,
                numCtx: nil,
                numPredict: nil,
                messageCount: nil,
                promptCharacterCount: nil
            )
        }

        let model = stringValue(object["model"])
        let messages = object["messages"] as? [[String: Any]]
        let messageContents = messages?.flatMap { messageContentStrings(from: $0["content"]) } ?? []
        let prompt = stringValue(object["prompt"])
        let options = object["options"] as? [String: Any]

        return OllamaProxyRequestMetadata(
            model: model,
            path: path,
            bodyByteCount: body.count,
            stream: object["stream"] as? Bool,
            numCtx: integerValue(options?["num_ctx"] ?? object["num_ctx"]),
            numPredict: integerValue(options?["num_predict"] ?? object["num_predict"]),
            messageCount: messages?.count,
            promptCharacterCount: prompt.map(\.count) ?? (messageContents.isEmpty ? nil : messageContents.reduce(0) { $0 + $1.count })
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func messageContentStrings(from value: Any?) -> [String] {
        if let string = stringValue(value) {
            return [string]
        }
        guard let parts = value as? [[String: Any]] else { return [] }
        return parts.compactMap { part in
            stringValue(part["text"])
        }
    }
}
