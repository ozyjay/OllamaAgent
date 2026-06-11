import Foundation
import Network

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
            model: metadata.modelDisplayName,
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
