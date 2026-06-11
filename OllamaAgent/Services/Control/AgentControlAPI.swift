import Foundation

struct AgentHealthResponse: Codable, Equatable {
    let dashboard: String
    let ollamaReachable: Bool
    let proxyRunning: Bool
    let baseURL: String
    let proxyURL: String
    let activeRequests: Int
    let lastRefresh: String?
    let message: String?
}

struct AgentModelResponse: Codable, Equatable {
    let name: String
    let displayName: String?
    let running: Bool
    let maxContext: Int?
}

struct AgentProfileResponse: Codable, Equatable {
    let id: String
    let name: String
    let purpose: String
    let preferredModel: String?
}

struct AgentChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct AgentContextStats: Codable, Equatable {
    let sourceCount: Int
    let characterCount: Int
    let estimatedTokenCount: Int
}

struct AgentChatRequest: Codable, Equatable {
    let requestId: String
    let surface: String
    let model: String?
    let profileId: String?
    let messages: [AgentChatMessage]
    let options: [String: JSONValue]
    let contextStats: AgentContextStats?
}

struct AgentCompletionRequest: Codable, Equatable {
    let requestId: String
    let languageId: String
    let fileName: String
    let prompt: String
    let options: [String: JSONValue]
    let contextStats: AgentContextStats
}

struct AgentCompletionResponse: Codable, Equatable {
    struct Stopped: Codable, Equatable {
        let reason: String
        let message: String
    }

    let requestId: String
    let text: String
    let stopped: Stopped?
}

struct AgentStreamEvent: Codable, Equatable {
    let type: String
    let requestId: String
    let model: String?
    let text: String?
    let reason: String?
    let message: String?
    let diagnosticId: String?
    let summary: String?

    static func started(requestId: String, model: String?) -> AgentStreamEvent {
        AgentStreamEvent(type: "started", requestId: requestId, model: model, text: nil, reason: nil, message: nil, diagnosticId: nil, summary: nil)
    }

    static func token(requestId: String, text: String) -> AgentStreamEvent {
        AgentStreamEvent(type: "token", requestId: requestId, model: nil, text: text, reason: nil, message: nil, diagnosticId: nil, summary: nil)
    }

    static func stopped(requestId: String, reason: String, message: String, diagnosticId: String? = nil) -> AgentStreamEvent {
        AgentStreamEvent(type: "stopped", requestId: requestId, model: nil, text: nil, reason: reason, message: message, diagnosticId: diagnosticId, summary: nil)
    }

    static func done(requestId: String, diagnosticId: String? = nil) -> AgentStreamEvent {
        AgentStreamEvent(type: "done", requestId: requestId, model: nil, text: nil, reason: nil, message: nil, diagnosticId: diagnosticId, summary: nil)
    }
}

@MainActor
enum AgentControlAPI {
    static func health(runtime: AgentRuntime) -> AgentHealthResponse {
        AgentHealthResponse(
            dashboard: "online",
            ollamaReachable: runtime.monitor.isReachable,
            proxyRunning: runtime.proxy.isRunning,
            baseURL: runtime.settings.baseURLString,
            proxyURL: runtime.proxy.proxyURLString,
            activeRequests: runtime.proxy.activeRequests.count,
            lastRefresh: runtime.monitor.lastRefresh.map(DurationFormatter.date),
            message: runtime.monitor.errorMessage
        )
    }

    static func models(runtime: AgentRuntime) -> [AgentModelResponse] {
        let runningNames = Set(runtime.monitor.runningModels.map(\.name))
        return runtime.monitor.installedModels.map { model in
            let running = runningNames.contains(model.name)
            return AgentModelResponse(
                name: model.name,
                displayName: model.name,
                running: running,
                maxContext: runtime.monitor.runningModels.first { $0.name == model.name }?.contextLength
            )
        }
    }

    static func profiles(runtime: AgentRuntime) -> [AgentProfileResponse] {
        runtime.profiles.profiles.map { profile in
            AgentProfileResponse(
                id: profile.id.uuidString,
                name: profile.name,
                purpose: profile.purpose,
                preferredModel: profile.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : profile.preferredModel
            )
        }
    }

    static func preflightEvents(for request: AgentChatRequest, runtime: AgentRuntime) async -> [AgentStreamEvent] {
        let model = selectedModel(for: request, runtime: runtime)
        let metadata = metadata(for: request, path: "/v1/chat/completions", model: model)
        let decision = runtime.settings.promptGuardrailPolicy.evaluate(metadata)
        guard decision.outcome != .blocked else {
            return [
                .started(requestId: request.requestId, model: model),
                .stopped(
                    requestId: request.requestId,
                    reason: "context_limit",
                    message: PromptGuardrailResponder.message(for: metadata, decision: decision)
                )
            ]
        }
        return [.started(requestId: request.requestId, model: model)]
    }

    static func selectedModel(for request: AgentChatRequest, runtime: AgentRuntime) -> String {
        if let model = request.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            return model
        }
        if let profileId = request.profileId,
           let uuid = UUID(uuidString: profileId),
           let profile = runtime.profiles.profiles.first(where: { $0.id == uuid }) {
            let preferred = profile.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preferred.isEmpty {
                return preferred
            }
        }
        return runtime.monitor.installedModels.first?.name
            ?? runtime.monitor.runningModels.first?.name
            ?? "llama3.2"
    }

    static func metadata(for request: AgentChatRequest, path: String, model: String) -> OllamaProxyRequestMetadata {
        let promptCharacters = request.messages.reduce(0) { total, message in
            total + message.content.count
        }
        return OllamaProxyRequestMetadata(
            model: model,
            path: path,
            bodyByteCount: promptCharacters,
            stream: false,
            numCtx: nil,
            numPredict: request.options["max_tokens"]?.integerValue ?? request.options["maxTokens"]?.integerValue,
            messageCount: request.messages.count,
            promptCharacterCount: request.contextStats?.characterCount ?? promptCharacters
        )
    }
}
