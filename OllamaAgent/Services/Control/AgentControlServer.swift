import Foundation
import Network

@MainActor
final class AgentControlServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Control API stopped."

    private let port: UInt16
    private var listener: NWListener?
    private weak var runtime: AgentRuntime?
    private var activeRequestIDs: Set<String> = []
    private var cancelledRequestIDs: Set<String> = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(port: UInt16 = 11_436) {
        self.port = port
    }

    func start(runtime: AgentRuntime) {
        self.runtime = runtime
        guard listener == nil else { return }
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                statusMessage = "Control API port \(port) is not valid."
                return
            }
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.handle(connection: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.statusMessage = "Control API listening at http://localhost:\(self?.port ?? 0)."
                    case .failed(let error):
                        self?.isRunning = false
                        self?.statusMessage = "Control API failed: \(error.localizedDescription)"
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .global(qos: .userInitiated))
            statusMessage = "Starting control API at http://localhost:\(port)..."
        } catch {
            statusMessage = "Control API failed: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        activeRequestIDs = []
        cancelledRequestIDs = []
        statusMessage = "Control API stopped."
    }

    private func handle(connection: NWConnection) async {
        connection.start(queue: .global(qos: .userInitiated))
        do {
            let request = try await OllamaProxyHTTPReader.readRequest(from: connection)
            try await route(request, connection: connection)
        } catch {
            try? await connection.sendHTTPStatus(500, body: "OllamaAgent control API error: \(error.localizedDescription)\n")
        }
        connection.cancel()
    }

    private func route(_ request: OllamaProxyHTTPRequest, connection: NWConnection) async throws {
        guard let runtime else {
            try await connection.sendHTTPStatus(503, body: "OllamaAgent runtime is not ready.\n")
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            try await connection.sendJSON(AgentControlAPI.health(runtime: runtime), encoder: encoder)
        case ("GET", "/v1/models"):
            try await connection.sendJSON(AgentControlAPI.models(runtime: runtime), encoder: encoder)
        case ("GET", "/v1/profiles"):
            try await connection.sendJSON(AgentControlAPI.profiles(runtime: runtime), encoder: encoder)
        case ("POST", "/v1/chat/stream"):
            let chatRequest = try decoder.decode(AgentChatRequest.self, from: request.body)
            try await streamChat(chatRequest, runtime: runtime, connection: connection)
        case ("POST", "/v1/complete"):
            let completionRequest = try decoder.decode(AgentCompletionRequest.self, from: request.body)
            try await complete(completionRequest, runtime: runtime, connection: connection)
        default:
            if request.method == "POST", request.path.hasPrefix("/v1/requests/"), request.path.hasSuffix("/cancel") {
                let id = request.path
                    .replacingOccurrences(of: "/v1/requests/", with: "")
                    .replacingOccurrences(of: "/cancel", with: "")
                    .removingPercentEncoding ?? ""
                cancelledRequestIDs.insert(id)
                activeRequestIDs.remove(id)
                try await connection.sendJSON(["cancelled": true], encoder: encoder)
            } else {
                try await connection.sendHTTPStatus(404, body: "Unknown OllamaAgent control API route.\n")
            }
        }
    }

    private func streamChat(_ request: AgentChatRequest, runtime: AgentRuntime, connection: NWConnection) async throws {
        activeRequestIDs.insert(request.requestId)
        cancelledRequestIDs.remove(request.requestId)
        defer { activeRequestIDs.remove(request.requestId) }

        try await connection.sendHTTPHead(contentType: "application/x-ndjson")
        let preflight = await AgentControlAPI.preflightEvents(for: request, runtime: runtime)
        for event in preflight {
            try await connection.sendNDJSON(event, encoder: encoder)
        }
        guard preflight.last?.type != "stopped" else { return }
        guard !cancelledRequestIDs.contains(request.requestId) else {
            try await connection.sendNDJSON(AgentStreamEvent.stopped(requestId: request.requestId, reason: "cancelled", message: "Cancelled."), encoder: encoder)
            return
        }

        do {
            let text = try await sendChatToOllama(request, runtime: runtime)
            if cancelledRequestIDs.contains(request.requestId) {
                try await connection.sendNDJSON(AgentStreamEvent.stopped(requestId: request.requestId, reason: "cancelled", message: "Cancelled."), encoder: encoder)
                return
            }
            if !text.isEmpty {
                try await connection.sendNDJSON(AgentStreamEvent.token(requestId: request.requestId, text: text), encoder: encoder)
            }
            try await connection.sendNDJSON(AgentStreamEvent.done(requestId: request.requestId), encoder: encoder)
        } catch {
            let diagnosticId = UUID().uuidString
            let message = "OllamaAgent stopped the response gracefully because Ollama failed: \(error.localizedDescription). Try narrowing context, switching profile/model, or checking the Ollama service."
            try await connection.sendNDJSON(AgentStreamEvent.stopped(requestId: request.requestId, reason: "ollama_failure", message: message, diagnosticId: diagnosticId), encoder: encoder)
        }
    }

    private func complete(_ request: AgentCompletionRequest, runtime: AgentRuntime, connection: NWConnection) async throws {
        let chatRequest = AgentChatRequest(
            requestId: request.requestId,
            surface: "inline",
            model: nil,
            profileId: nil,
            messages: [AgentChatMessage(role: "user", content: request.prompt)],
            options: request.options,
            contextStats: request.contextStats
        )
        let preflight = await AgentControlAPI.preflightEvents(for: chatRequest, runtime: runtime)
        if let stopped = preflight.first(where: { $0.type == "stopped" }) {
            let response = AgentCompletionResponse(
                requestId: request.requestId,
                text: "",
                stopped: .init(reason: stopped.reason ?? "context_limit", message: stopped.message ?? "Completion stopped.")
            )
            try await connection.sendJSON(response, encoder: encoder)
            return
        }

        do {
            let text = try await sendChatToOllama(chatRequest, runtime: runtime)
            try await connection.sendJSON(AgentCompletionResponse(requestId: request.requestId, text: text, stopped: nil), encoder: encoder)
        } catch {
            try await connection.sendJSON(
                AgentCompletionResponse(
                    requestId: request.requestId,
                    text: "",
                    stopped: .init(reason: "ollama_failure", message: "Inline completion stopped because Ollama failed.")
                ),
                encoder: encoder
            )
        }
    }

    private func sendChatToOllama(_ request: AgentChatRequest, runtime: AgentRuntime) async throws -> String {
        let model = AgentControlAPI.selectedModel(for: request, runtime: runtime)
        var url = runtime.settings.baseURL
        url.append(path: "api/chat")
        var apiRequest = URLRequest(url: url, timeoutInterval: request.surface == "inline" ? 8 : 300)
        apiRequest.httpMethod = "POST"
        apiRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        apiRequest.httpBody = try encoder.encode(OllamaChatBody(
            model: model,
            messages: request.messages.map { OllamaChatBody.Message(role: $0.role, content: $0.content) },
            stream: false,
            options: request.options.isEmpty ? nil : request.options
        ))

        let (data, response) = try await URLSession.shared.data(for: apiRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaAPIError.badStatus(http.statusCode)
        }
        return try decoder.decode(OllamaChatResponse.self, from: data).message.content
    }
}

private struct OllamaChatBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
    let options: [String: JSONValue]?
}

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable {
        let role: String?
        let content: String
    }

    let message: Message
}

private extension NWConnection {
    func sendHTTPHead(contentType: String) async throws {
        let head = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Connection: close\r
        \r

        """
        try await sendData(Data(head.utf8))
    }

    func sendJSON<T: Encodable>(_ value: T, encoder: JSONEncoder) async throws {
        let body = try encoder.encode(value)
        let head = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        try await sendData(Data(head.utf8) + body)
    }

    func sendNDJSON<T: Encodable>(_ value: T, encoder: JSONEncoder) async throws {
        var line = try encoder.encode(value)
        line.append(0x0A)
        try await sendData(line)
    }
}
