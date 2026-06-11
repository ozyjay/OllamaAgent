import Foundation
import Network

@MainActor
final class OllamaServiceMonitor: ObservableObject {
    @Published var version: OllamaVersion?
    @Published var installedModels: [InstalledModel] = []
    @Published var runningModels: [RunningModel] = []
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var isRefreshing = false

    private let settings: AppSettings
    private let apiClientFactory: (URL) -> any OllamaAPIClientProviding
    private let cliClientFactory: (String) -> any OllamaCLIClientProviding

    init(
        settings: AppSettings,
        apiClientFactory: @escaping (URL) -> any OllamaAPIClientProviding = { OllamaAPIClient(baseURL: $0) },
        cliClientFactory: @escaping (String) -> any OllamaCLIClientProviding = { OllamaCLIClient(executablePath: $0) }
    ) {
        self.settings = settings
        self.apiClientFactory = apiClientFactory
        self.cliClientFactory = cliClientFactory
    }

    var isReachable: Bool {
        version != nil && errorMessage == nil
    }

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let client = apiClientFactory(settings.baseURL)
        do {
            self.version = try await client.getVersion()
            installedModels = try await client.getInstalledModels()
            runningModels = try await client.getRunningModels()
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            version = nil
            installedModels = []
            runningModels = []
            errorMessage = friendlyMessage(for: error)
        }
    }

    func warm(model: String, keepAlive: String, numCtx: Int?, options: [String: JSONValue] = [:]) async -> String {
        do {
            let client = apiClientFactory(settings.baseURL)
            _ = try await client.warmModel(name: model, keepAlive: keepAlive, numCtx: numCtx, options: options)
            await refreshAll()
            return "Warmed \(model)."
        } catch {
            return friendlyMessage(for: error)
        }
    }

    func unload(model: String) async -> String {
        let client = apiClientFactory(settings.baseURL)
        do {
            _ = try await client.unloadModelViaAPI(name: model)
            await refreshAll()
            return "Unloaded \(model) via API."
        } catch {
            guard settings.enableCLIControls else {
                return "API unload failed. Enable CLI-backed controls to try ollama stop."
            }
            do {
                let cli = cliClientFactory(settings.ollamaCLIPath)
                try await cli.stopModel(name: model)
                await refreshAll()
                return "Stopped \(model) with ollama CLI."
            } catch {
                return friendlyMessage(for: error)
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "Ollama is unreachable. Confirm it is running at \(settings.baseURLString)."
    }
}

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

@MainActor
final class OllamaProxyServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Proxy stopped."
    @Published private(set) var activeRequests: [OllamaProxyRequest] = []
    @Published private(set) var diagnosticRecords: [OllamaProxyRequestRecord] = []

    private var listener: NWListener?
    private var currentPort: Int?
    private var currentTarget: URL?
    private var currentGuardrailPolicy = PromptGuardrailPolicy.disabled()
    private let maxDiagnosticRecords = 50

    var activeModelNames: Set<String> {
        Set(activeRequests.map(\.model))
    }

    var proxyURLString: String {
        "http://localhost:\(currentPort ?? 11_435)"
    }

    func apply(settings: AppSettings) async {
        currentGuardrailPolicy = settings.promptGuardrailPolicy
        guard settings.enableProxy else {
            stop()
            return
        }
        start(port: settings.proxyPort, target: settings.baseURL)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        activeRequests = []
        statusMessage = "Proxy stopped."
    }

    func clearDiagnostics() {
        diagnosticRecords = []
    }

    func diagnosticsSummary() -> String {
        guard !diagnosticRecords.isEmpty else { return "No proxy diagnostics captured." }
        return diagnosticRecords.map { record in
            let guardrailReasons = record.guardrailReasons.joined(separator: "; ")
            let guardrailReasonSummary = record.guardrailReasons.isEmpty ? nil : "reasons \(guardrailReasons)"
            return [
                DurationFormatter.date(record.startedAt),
                record.model,
                record.path,
                "status \(record.statusText)",
                String(format: "%.1fs", record.duration),
                "\(record.bodyByteCount) bytes",
                record.messageCount.map { "\($0) messages" },
                record.promptCharacterCount.map { "\($0) prompt chars" },
                record.stream.map { "stream \($0)" },
                record.numCtx.map { "num_ctx \($0)" },
                record.numPredict.map { "num_predict \($0)" },
                record.estimatedTokenCount.map { "estimated_tokens \($0)" },
                "guardrail \(record.guardrailOutcome.rawValue)",
                guardrailReasonSummary,
                record.isLikelyProviderTimeout ? "likely provider timeout" : nil,
                record.proxyError.map { "error \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: " | ")
        }
        .joined(separator: "\n")
    }

    func recordDiagnostic(
        metadata: OllamaProxyRequestMetadata,
        startedAt: Date,
        endedAt: Date,
        upstreamStatusCode: Int?,
        proxyError: String?,
        guardrailDecision: PromptGuardrailDecision = .allowed
    ) {
        let record = OllamaProxyRequestRecord(
            id: UUID(),
            model: metadata.model ?? "Unknown model",
            path: metadata.path,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: endedAt.timeIntervalSince(startedAt),
            upstreamStatusCode: upstreamStatusCode,
            proxyError: proxyError,
            bodyByteCount: metadata.bodyByteCount,
            stream: metadata.stream,
            numCtx: metadata.numCtx,
            numPredict: metadata.numPredict,
            messageCount: metadata.messageCount,
            promptCharacterCount: metadata.promptCharacterCount,
            estimatedTokenCount: guardrailDecision.estimatedTokenCount,
            guardrailOutcome: guardrailDecision.outcome,
            guardrailReasons: guardrailDecision.reasons
        )
        diagnosticRecords.append(record)
        if diagnosticRecords.count > maxDiagnosticRecords {
            diagnosticRecords.removeFirst(diagnosticRecords.count - maxDiagnosticRecords)
        }
    }

    private func start(port: Int, target: URL) {
        guard port > 0, port <= Int(UInt16.max) else {
            stop()
            statusMessage = "Proxy port must be between 1 and \(UInt16.max)."
            return
        }
        if isRunning, currentPort == port, currentTarget == target {
            return
        }
        stop()

        do {
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
                statusMessage = "Proxy port \(port) is not valid."
                return
            }
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.handle(connection: connection, target: target)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.statusMessage = "Proxy listening at http://localhost:\(port)."
                    case .failed(let error):
                        self?.isRunning = false
                        self?.statusMessage = "Proxy failed: \(error.localizedDescription)"
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            currentPort = port
            currentTarget = target
            self.listener = listener
            listener.start(queue: .global(qos: .userInitiated))
            statusMessage = "Starting proxy at http://localhost:\(port)..."
        } catch {
            statusMessage = "Proxy failed: \(error.localizedDescription)"
        }
    }

    private func handle(connection: NWConnection, target: URL) async {
        connection.start(queue: .global(qos: .userInitiated))
        var trackedID: UUID?
        var metadata: OllamaProxyRequestMetadata?
        var guardrailDecision = PromptGuardrailDecision.allowed
        let startedAt = Date()
        do {
            let request = try await OllamaProxyHTTPReader.readRequest(from: connection)
            let requestMetadata = OllamaProxyRequestParser.metadata(path: request.path, body: request.body)
            metadata = requestMetadata
            guardrailDecision = currentGuardrailPolicy.evaluate(requestMetadata)
            if guardrailDecision.outcome == .blocked {
                recordDiagnostic(
                    metadata: requestMetadata,
                    startedAt: startedAt,
                    endedAt: Date(),
                    upstreamStatusCode: nil,
                    proxyError: nil,
                    guardrailDecision: guardrailDecision
                )
                let response = PromptGuardrailResponder.response(for: requestMetadata, decision: guardrailDecision)
                try await connection.sendHTTPResponse(response)
                connection.cancel()
                return
            }

            let modelName = requestMetadata.model
            if let modelName {
                let id = UUID()
                trackedID = id
                activeRequests.append(
                    OllamaProxyRequest(id: id, model: modelName, path: request.path, startedAt: startedAt)
                )
            }
            let statusCode = try await OllamaProxyForwarder.forward(request, to: target, connection: connection)
            recordDiagnostic(
                metadata: requestMetadata,
                startedAt: startedAt,
                endedAt: Date(),
                upstreamStatusCode: statusCode,
                proxyError: nil,
                guardrailDecision: guardrailDecision
            )
        } catch {
            if let metadata {
                let forwardFailure = error as? OllamaProxyForwardFailure
                recordDiagnostic(
                    metadata: metadata,
                    startedAt: startedAt,
                    endedAt: Date(),
                    upstreamStatusCode: forwardFailure?.statusCode,
                    proxyError: forwardFailure?.underlyingDescription ?? error.localizedDescription,
                    guardrailDecision: guardrailDecision
                )
            }
            try? await connection.sendHTTPStatus(502, body: "Ollama proxy error: \(error.localizedDescription)\n")
        }
        if let trackedID {
            activeRequests.removeAll { $0.id == trackedID }
        }
        connection.cancel()
    }
}

private struct OllamaProxyHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private enum OllamaProxyError: LocalizedError {
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

private struct OllamaProxyForwardFailure: LocalizedError {
    let statusCode: Int?
    let underlyingDescription: String

    var errorDescription: String? {
        underlyingDescription
    }
}

private enum OllamaProxyHTTPReader {
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

private enum OllamaProxyForwarder {
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

private extension NWConnection {
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
