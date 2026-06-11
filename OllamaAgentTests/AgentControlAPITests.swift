import XCTest
@testable import OllamaAgent

@MainActor
final class AgentControlAPITests: XCTestCase {
    func testHealthResponseSummarizesRuntimeWithoutPromptContent() throws {
        let runtime = AgentRuntime(
            settings: AppSettings(defaults: UserDefaults(suiteName: "agent-control-health-\(UUID().uuidString)")!),
            profiles: ProfileManager(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            proxy: OllamaProxyServer()
        )
        let response = AgentControlAPI.health(runtime: runtime)

        XCTAssertEqual(response.dashboard, "online")
        XCTAssertEqual(response.baseURL, "http://localhost:11434")
        XCTAssertEqual(response.proxyURL, "http://localhost:11435")
    }

    func testOversizedChatRequestStopsBeforeOllama() async throws {
        let runtime = AgentRuntime(
            settings: AppSettings(defaults: UserDefaults(suiteName: "agent-control-stop-\(UUID().uuidString)")!),
            profiles: ProfileManager(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            proxy: OllamaProxyServer()
        )
        runtime.settings.promptGuardrailBlockPromptCharacters = 10
        let request = AgentChatRequest(
            requestId: "r1",
            surface: "chat",
            model: "llama3.2",
            profileId: nil,
            messages: [AgentChatMessage(role: "user", content: "this prompt is too long")],
            options: [:],
            contextStats: AgentContextStats(sourceCount: 1, characterCount: 23, estimatedTokenCount: 6)
        )

        let events = await AgentControlAPI.preflightEvents(for: request, runtime: runtime)

        XCTAssertEqual(events.map(\.type), ["started", "stopped"])
        XCTAssertEqual(events.last?.reason, "context_limit")
        let message = try XCTUnwrap(events.last?.message)
        XCTAssertFalse(message.contains("this prompt is too long"))
    }
}
