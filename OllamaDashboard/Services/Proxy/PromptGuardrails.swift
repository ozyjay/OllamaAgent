import Foundation

enum PromptGuardrailOutcome: String, Equatable {
    case allowed
    case warned
    case blocked
}

struct PromptGuardrailDecision: Equatable {
    let outcome: PromptGuardrailOutcome
    let reasons: [String]
    let estimatedTokenCount: Int?
    let responseMode: PromptGuardrailResponseMode

    static let allowed = PromptGuardrailDecision(
        outcome: .allowed,
        reasons: [],
        estimatedTokenCount: nil,
        responseMode: .assistantMessage
    )

    var summary: String {
        guard !reasons.isEmpty else { return "guardrail allowed" }
        return reasons.joined(separator: "; ")
    }
}

struct PromptGuardrailPolicy: Equatable {
    let enabled: Bool
    let responseMode: PromptGuardrailResponseMode
    let warnPromptCharacters: Int
    let blockPromptCharacters: Int
    let warnBodyBytes: Int
    let blockBodyBytes: Int
    let warnMessages: Int
    let blockMessages: Int
    let warnContextRatio: Double
    let blockContextRatio: Double

    static let defaults = PromptGuardrailPolicy(
        enabled: true,
        responseMode: .assistantMessage,
        warnPromptCharacters: 120_000,
        blockPromptCharacters: 300_000,
        warnBodyBytes: 1_000_000,
        blockBodyBytes: 2_500_000,
        warnMessages: 20,
        blockMessages: 60,
        warnContextRatio: 0.75,
        blockContextRatio: 1.10
    )

    static func disabled(responseMode: PromptGuardrailResponseMode = .assistantMessage) -> PromptGuardrailPolicy {
        PromptGuardrailPolicy(
            enabled: false,
            responseMode: responseMode,
            warnPromptCharacters: Self.defaults.warnPromptCharacters,
            blockPromptCharacters: Self.defaults.blockPromptCharacters,
            warnBodyBytes: Self.defaults.warnBodyBytes,
            blockBodyBytes: Self.defaults.blockBodyBytes,
            warnMessages: Self.defaults.warnMessages,
            blockMessages: Self.defaults.blockMessages,
            warnContextRatio: Self.defaults.warnContextRatio,
            blockContextRatio: Self.defaults.blockContextRatio
        )
    }

    func evaluate(_ metadata: OllamaProxyRequestMetadata) -> PromptGuardrailDecision {
        let estimatedTokens = metadata.promptCharacterCount.map { Int(ceil(Double($0) / 4.0)) }
        guard enabled else {
            return PromptGuardrailDecision(
                outcome: .allowed,
                reasons: [],
                estimatedTokenCount: estimatedTokens,
                responseMode: responseMode
            )
        }

        var warningReasons: [String] = []
        var blockingReasons: [String] = []

        evaluate(
            label: "prompt characters",
            value: metadata.promptCharacterCount,
            warnThreshold: warnPromptCharacters,
            blockThreshold: blockPromptCharacters,
            warnings: &warningReasons,
            blocks: &blockingReasons
        )
        evaluate(
            label: "body bytes",
            value: metadata.bodyByteCount,
            warnThreshold: warnBodyBytes,
            blockThreshold: blockBodyBytes,
            warnings: &warningReasons,
            blocks: &blockingReasons
        )
        evaluate(
            label: "messages",
            value: metadata.messageCount,
            warnThreshold: warnMessages,
            blockThreshold: blockMessages,
            warnings: &warningReasons,
            blocks: &blockingReasons
        )

        if let estimatedTokens, let numCtx = metadata.numCtx, numCtx > 0 {
            let ratio = Double(estimatedTokens) / Double(numCtx)
            if ratio >= blockContextRatio {
                blockingReasons.append(
                    "estimated prompt tokens \(estimatedTokens) exceed \(Int(blockContextRatio * 100))% of num_ctx \(numCtx)"
                )
            } else if ratio >= warnContextRatio {
                warningReasons.append(
                    "estimated prompt tokens \(estimatedTokens) exceed \(Int(warnContextRatio * 100))% of num_ctx \(numCtx)"
                )
            }
        }

        if !blockingReasons.isEmpty {
            return PromptGuardrailDecision(
                outcome: .blocked,
                reasons: blockingReasons + warningReasons,
                estimatedTokenCount: estimatedTokens,
                responseMode: responseMode
            )
        }
        if !warningReasons.isEmpty {
            return PromptGuardrailDecision(
                outcome: .warned,
                reasons: warningReasons,
                estimatedTokenCount: estimatedTokens,
                responseMode: responseMode
            )
        }
        return PromptGuardrailDecision(
            outcome: .allowed,
            reasons: [],
            estimatedTokenCount: estimatedTokens,
            responseMode: responseMode
        )
    }

    private func evaluate(
        label: String,
        value: Int?,
        warnThreshold: Int,
        blockThreshold: Int,
        warnings: inout [String],
        blocks: inout [String]
    ) {
        guard let value else { return }
        if value >= blockThreshold {
            blocks.append("\(label) \(value) meet block threshold \(blockThreshold)")
        } else if value >= warnThreshold {
            warnings.append("\(label) \(value) meet warn threshold \(warnThreshold)")
        }
    }
}

struct PromptGuardrailHTTPResponse: Equatable {
    let statusCode: Int
    let contentType: String
    let body: Data
}

enum PromptGuardrailResponder {
    static func response(
        for metadata: OllamaProxyRequestMetadata,
        decision: PromptGuardrailDecision,
        date: Date = Date()
    ) -> PromptGuardrailHTTPResponse {
        if decision.responseMode == .httpError {
            return PromptGuardrailHTTPResponse(
                statusCode: 413,
                contentType: "text/plain; charset=utf-8",
                body: Data(message(for: metadata, decision: decision).utf8)
            )
        }

        let content = message(for: metadata, decision: decision)
        if metadata.path.contains("/v1/chat/completions") {
            return metadata.stream == true
                ? openAIStreamResponse(content: content, model: metadata.model)
                : openAIResponse(content: content, model: metadata.model, date: date)
        }
        if metadata.path.contains("/api/chat") {
            return metadata.stream == true
                ? ollamaChatStreamResponse(content: content, model: metadata.model, date: date)
                : ollamaChatResponse(content: content, model: metadata.model, date: date)
        }
        return metadata.stream == true
            ? ollamaGenerateStreamResponse(content: content, model: metadata.model, date: date)
            : ollamaGenerateResponse(content: content, model: metadata.model, date: date)
    }

    static func message(for metadata: OllamaProxyRequestMetadata, decision: PromptGuardrailDecision) -> String {
        var facts = [
            "\(metadata.bodyByteCount) body bytes"
        ]
        if let promptCharacterCount = metadata.promptCharacterCount {
            facts.append("\(promptCharacterCount) prompt chars")
        }
        if let estimatedTokenCount = decision.estimatedTokenCount {
            facts.append("about \(estimatedTokenCount) estimated prompt tokens")
        }
        if let messageCount = metadata.messageCount {
            facts.append("\(messageCount) messages")
        }
        if let numCtx = metadata.numCtx {
            facts.append("num_ctx \(numCtx)")
        }

        let reasons = decision.reasons.isEmpty
            ? "it exceeded the local prompt guardrail"
            : decision.reasons.joined(separator: "; ")
        return """
        OllamaDashboard blocked before reaching Ollama because the prompt looked too large for the selected local route. The request had \(facts.joined(separator: ", ")). Guardrail reasons: \(reasons). Try narrowing the review scope, starting a fresh chat, reviewing selected files first, or adding AGENTS.md / project overview docs so Copilot can use a smaller context.
        """
    }

    private static func openAIResponse(content: String, model: String?, date: Date) -> PromptGuardrailHTTPResponse {
        jsonResponse([
            "id": "chatcmpl-ollama-dashboard-guardrail",
            "object": "chat.completion",
            "created": Int(date.timeIntervalSince1970),
            "model": model ?? "ollama-dashboard-guardrail",
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": content],
                    "finish_reason": "stop"
                ]
            ]
        ])
    }

    private static func openAIStreamResponse(content: String, model: String?) -> PromptGuardrailHTTPResponse {
        let modelName = model ?? "ollama-dashboard-guardrail"
        let contentChoice: [String: Any] = [
            "index": 0,
            "delta": ["role": "assistant", "content": content],
            "finish_reason": NSNull()
        ]
        let stopChoice: [String: Any] = [
            "index": 0,
            "delta": [String: Any](),
            "finish_reason": "stop"
        ]
        let chunk: [String: Any] = [
            "id": "chatcmpl-ollama-dashboard-guardrail",
            "object": "chat.completion.chunk",
            "model": modelName,
            "choices": [contentChoice]
        ]
        let stop: [String: Any] = [
            "id": "chatcmpl-ollama-dashboard-guardrail",
            "object": "chat.completion.chunk",
            "model": modelName,
            "choices": [stopChoice]
        ]
        let body = "data: \(jsonString(chunk))\n\ndata: \(jsonString(stop))\n\ndata: [DONE]\n\n"
        return PromptGuardrailHTTPResponse(
            statusCode: 200,
            contentType: "text/event-stream; charset=utf-8",
            body: Data(body.utf8)
        )
    }

    private static func ollamaChatResponse(content: String, model: String?, date: Date) -> PromptGuardrailHTTPResponse {
        jsonResponse([
            "model": model ?? "ollama-dashboard-guardrail",
            "created_at": ISO8601DateFormatter().string(from: date),
            "message": ["role": "assistant", "content": content],
            "done": true
        ])
    }

    private static func ollamaChatStreamResponse(content: String, model: String?, date: Date) -> PromptGuardrailHTTPResponse {
        let object: [String: Any] = [
            "model": model ?? "ollama-dashboard-guardrail",
            "created_at": ISO8601DateFormatter().string(from: date),
            "message": ["role": "assistant", "content": content],
            "done": true
        ]
        return jsonLineResponse(object)
    }

    private static func ollamaGenerateResponse(content: String, model: String?, date: Date) -> PromptGuardrailHTTPResponse {
        jsonResponse([
            "model": model ?? "ollama-dashboard-guardrail",
            "created_at": ISO8601DateFormatter().string(from: date),
            "response": content,
            "done": true
        ])
    }

    private static func ollamaGenerateStreamResponse(content: String, model: String?, date: Date) -> PromptGuardrailHTTPResponse {
        let object: [String: Any] = [
            "model": model ?? "ollama-dashboard-guardrail",
            "created_at": ISO8601DateFormatter().string(from: date),
            "response": content,
            "done": true
        ]
        return jsonLineResponse(object)
    }

    private static func jsonResponse(_ object: [String: Any]) -> PromptGuardrailHTTPResponse {
        PromptGuardrailHTTPResponse(
            statusCode: 200,
            contentType: "application/json",
            body: jsonData(object)
        )
    }

    private static func jsonLineResponse(_ object: [String: Any]) -> PromptGuardrailHTTPResponse {
        PromptGuardrailHTTPResponse(
            statusCode: 200,
            contentType: "application/x-ndjson",
            body: Data((jsonString(object) + "\n").utf8)
        )
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        String(decoding: jsonData(object), as: UTF8.self)
    }

    private static func jsonData(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
