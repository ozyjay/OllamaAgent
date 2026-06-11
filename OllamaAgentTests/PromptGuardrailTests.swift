import XCTest
@testable import OllamaAgent

final class PromptGuardrailTests: XCTestCase {
    func testPromptGuardrailPolicyAllowsSmallPrompts() {
        let metadata = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/api/generate",
            bodyByteCount: 512,
            stream: false,
            numCtx: 8_192,
            numPredict: 128,
            messageCount: nil,
            promptCharacterCount: 1_000
        )

        let decision = PromptGuardrailPolicy.defaults.evaluate(metadata)

        XCTAssertEqual(decision.outcome, .allowed)
        XCTAssertEqual(decision.estimatedTokenCount, 250)
        XCTAssertTrue(decision.reasons.isEmpty)
    }

    func testPromptGuardrailPolicyWarnsAndBlocksAtScaleThresholds() {
        let warnMetadata = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/v1/chat/completions",
            bodyByteCount: 1_100_000,
            stream: false,
            numCtx: nil,
            numPredict: nil,
            messageCount: 21,
            promptCharacterCount: 130_000
        )
        let blockMetadata = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/v1/chat/completions",
            bodyByteCount: 2_700_000,
            stream: false,
            numCtx: nil,
            numPredict: nil,
            messageCount: 61,
            promptCharacterCount: 310_000
        )

        let warnDecision = PromptGuardrailPolicy.defaults.evaluate(warnMetadata)
        let blockDecision = PromptGuardrailPolicy.defaults.evaluate(blockMetadata)

        XCTAssertEqual(warnDecision.outcome, .warned)
        XCTAssertTrue(warnDecision.summary.contains("prompt characters"))
        XCTAssertEqual(blockDecision.outcome, .blocked)
        XCTAssertTrue(blockDecision.summary.contains("body bytes"))
        XCTAssertFalse(blockDecision.summary.contains("qwen3"))
    }

    func testPromptGuardrailPolicyUsesPromptToContextRatio() {
        let warning = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/api/chat",
            bodyByteCount: 10_000,
            stream: false,
            numCtx: 4_000,
            numPredict: nil,
            messageCount: 2,
            promptCharacterCount: 12_400
        )
        let blocked = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/api/chat",
            bodyByteCount: 10_000,
            stream: false,
            numCtx: 4_000,
            numPredict: nil,
            messageCount: 2,
            promptCharacterCount: 17_800
        )

        XCTAssertEqual(PromptGuardrailPolicy.defaults.evaluate(warning).outcome, .warned)
        XCTAssertEqual(PromptGuardrailPolicy.defaults.evaluate(blocked).outcome, .blocked)
    }

    func testPromptGuardrailPolicyFallsBackToBodySizeForInvalidJSONMetadata() {
        let metadata = OllamaProxyRequestParser.metadata(path: "/api/generate", body: Data(repeating: 65, count: 2_700_000))

        let decision = PromptGuardrailPolicy.defaults.evaluate(metadata)

        XCTAssertEqual(decision.outcome, .blocked)
        XCTAssertNil(decision.estimatedTokenCount)
        XCTAssertTrue(decision.summary.contains("body bytes"))
    }

    func testPromptGuardrailResponderBuildsEndpointCompatibleResponses() throws {
        let metadata = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/v1/chat/completions",
            bodyByteCount: 2_700_000,
            stream: false,
            numCtx: 4_000,
            numPredict: nil,
            messageCount: 61,
            promptCharacterCount: 310_000
        )
        let decision = PromptGuardrailPolicy.defaults.evaluate(metadata)

        let openAI = PromptGuardrailResponder.response(for: metadata, decision: decision)
        let openAIObject = try XCTUnwrap(JSONSerialization.jsonObject(with: openAI.body) as? [String: Any])
        let choices = try XCTUnwrap(openAIObject["choices"] as? [[String: Any]])
        let message = try XCTUnwrap(choices.first?["message"] as? [String: Any])
        let content = try XCTUnwrap(message["content"] as? String)
        XCTAssertEqual(openAI.contentType, "application/json")
        XCTAssertTrue(content.contains("blocked before reaching Ollama"))
        XCTAssertTrue(content.contains("310000 prompt chars"))
        XCTAssertFalse(content.contains("secret"))

        let openAIStreamMetadata = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/v1/chat/completions",
            bodyByteCount: 2_700_000,
            stream: true,
            numCtx: 4_000,
            numPredict: nil,
            messageCount: 61,
            promptCharacterCount: 310_000
        )
        let openAIStream = PromptGuardrailResponder.response(for: openAIStreamMetadata, decision: decision)
        let openAIStreamText = String(decoding: openAIStream.body, as: UTF8.self)
        XCTAssertEqual(openAIStream.contentType, "text/event-stream; charset=utf-8")
        XCTAssertTrue(openAIStreamText.contains("data: "))
        XCTAssertTrue(openAIStreamText.hasSuffix("data: [DONE]\n\n"))

        let ollamaChatMetadata = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/api/chat",
            bodyByteCount: 2_700_000,
            stream: false,
            numCtx: 4_000,
            numPredict: nil,
            messageCount: 61,
            promptCharacterCount: 310_000
        )
        let ollamaChat = PromptGuardrailResponder.response(for: ollamaChatMetadata, decision: decision)
        let chatObject = try XCTUnwrap(JSONSerialization.jsonObject(with: ollamaChat.body) as? [String: Any])
        XCTAssertNotNil(chatObject["message"])

        let ollamaGenerateMetadata = OllamaProxyRequestMetadata(
            model: "qwen3:latest",
            path: "/api/generate",
            bodyByteCount: 2_700_000,
            stream: false,
            numCtx: 4_000,
            numPredict: nil,
            messageCount: nil,
            promptCharacterCount: 310_000
        )
        let ollamaGenerate = PromptGuardrailResponder.response(for: ollamaGenerateMetadata, decision: decision)
        let generateObject = try XCTUnwrap(JSONSerialization.jsonObject(with: ollamaGenerate.body) as? [String: Any])
        XCTAssertNotNil(generateObject["response"])
    }
}
