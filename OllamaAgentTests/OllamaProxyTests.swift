import XCTest
@testable import OllamaAgent

@MainActor
final class OllamaProxyTests: XCTestCase {
    func testProxyRequestParserExtractsModelFromJSONBodies() {
        XCTAssertEqual(
            OllamaProxyRequestParser.modelName(from: Data(#"{"model":"qwen3:latest","prompt":"hi"}"#.utf8)),
            "qwen3:latest"
        )
        XCTAssertEqual(
            OllamaProxyRequestParser.modelName(from: Data(#"{"model":"  "}"#.utf8)),
            nil
        )
        XCTAssertEqual(OllamaProxyRequestParser.modelName(from: Data("not json".utf8)), nil)
    }

    func testProxyRequestMetadataParsesGeneratePromptAndOptionsWithoutStoringPromptText() {
        let body = Data(#"{"model":"qwen3:latest","prompt":"secret prompt text","stream":true,"options":{"num_ctx":32768,"num_predict":512}}"#.utf8)

        let metadata = OllamaProxyRequestParser.metadata(path: "/api/generate", body: body)

        XCTAssertEqual(metadata.model, "qwen3:latest")
        XCTAssertEqual(metadata.path, "/api/generate")
        XCTAssertEqual(metadata.bodyByteCount, body.count)
        XCTAssertEqual(metadata.stream, true)
        XCTAssertEqual(metadata.numCtx, 32_768)
        XCTAssertEqual(metadata.numPredict, 512)
        XCTAssertNil(metadata.messageCount)
        XCTAssertEqual(metadata.promptCharacterCount, "secret prompt text".count)
        XCTAssertFalse(String(describing: metadata).contains("secret prompt text"))
    }

    func testProxyRequestMetadataParsesChatMessagesWithoutStoringMessageText() {
        let body = Data(#"{"model":"qwen3:latest","messages":[{"role":"system","content":"private system"},{"role":"user","content":"private user"}],"stream":false,"options":{"num_ctx":8192}}"#.utf8)

        let metadata = OllamaProxyRequestParser.metadata(path: "/api/chat", body: body)

        XCTAssertEqual(metadata.model, "qwen3:latest")
        XCTAssertEqual(metadata.bodyByteCount, body.count)
        XCTAssertEqual(metadata.stream, false)
        XCTAssertEqual(metadata.numCtx, 8_192)
        XCTAssertNil(metadata.numPredict)
        XCTAssertEqual(metadata.messageCount, 2)
        XCTAssertEqual(metadata.promptCharacterCount, "private system".count + "private user".count)
        XCTAssertFalse(String(describing: metadata).contains("private system"))
        XCTAssertFalse(String(describing: metadata).contains("private user"))
    }

    func testProxyRequestMetadataParsesOpenAIChatCompletionsTopLevelOptions() {
        let body = Data(#"{"model":"qwen3:latest","messages":[{"role":"user","content":"private"}],"stream":true,"num_ctx":4096,"num_predict":128}"#.utf8)

        let metadata = OllamaProxyRequestParser.metadata(path: "/v1/chat/completions", body: body)

        XCTAssertEqual(metadata.model, "qwen3:latest")
        XCTAssertEqual(metadata.path, "/v1/chat/completions")
        XCTAssertEqual(metadata.stream, true)
        XCTAssertEqual(metadata.numCtx, 4_096)
        XCTAssertEqual(metadata.numPredict, 128)
        XCTAssertEqual(metadata.messageCount, 1)
        XCTAssertEqual(metadata.promptCharacterCount, "private".count)
        XCTAssertFalse(String(describing: metadata).contains("private"))
    }

    func testProxyRequestMetadataFallsBackToBodySizeForInvalidJSON() {
        let body = Data("not json".utf8)

        let metadata = OllamaProxyRequestParser.metadata(path: "/api/generate", body: body)

        XCTAssertNil(metadata.model)
        XCTAssertEqual(metadata.path, "/api/generate")
        XCTAssertEqual(metadata.bodyByteCount, body.count)
        XCTAssertNil(metadata.stream)
        XCTAssertNil(metadata.numCtx)
        XCTAssertNil(metadata.numPredict)
        XCTAssertNil(metadata.messageCount)
        XCTAssertNil(metadata.promptCharacterCount)
    }

    func testProxyDiagnosticUsesActionableLabelWhenModelIsMissing() {
        let proxy = OllamaProxyServer()
        let startedAt = Date(timeIntervalSince1970: 900)
        let metadata = OllamaProxyRequestParser.metadata(
            path: "/v1/chat/completions",
            body: Data(#"{"messages":[{"role":"user","content":"private"}]}"#.utf8)
        )

        proxy.recordDiagnostic(
            metadata: metadata,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1),
            upstreamStatusCode: 400,
            proxyError: nil
        )

        XCTAssertEqual(proxy.diagnosticRecords[0].model, "No model in request")
        XCTAssertTrue(proxy.diagnosticsSummary().contains("No model in request"))
        XCTAssertFalse(proxy.diagnosticsSummary().contains("Unknown model"))
        XCTAssertFalse(proxy.diagnosticsSummary().contains("private"))
    }

    func testProxyDiagnosticRecordsSummarizeFailuresAndCapHistory() {
        let proxy = OllamaProxyServer()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let metadata = OllamaProxyRequestParser.metadata(
            path: "/v1/chat/completions",
            body: Data(#"{"model":"qwen3:latest","messages":[{"role":"user","content":"private"}]}"#.utf8)
        )

        proxy.recordDiagnostic(
            metadata: metadata,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            upstreamStatusCode: 500,
            proxyError: nil,
            guardrailDecision: .allowed
        )

        XCTAssertEqual(proxy.diagnosticRecords.count, 1)
        XCTAssertEqual(proxy.diagnosticRecords[0].duration, 60)
        XCTAssertTrue(proxy.diagnosticRecords[0].isLikelyProviderTimeout)
        XCTAssertEqual(proxy.diagnosticRecords[0].guardrailOutcome, .allowed)
        XCTAssertFalse(proxy.diagnosticsSummary().contains("private"))

        for index in 0..<55 {
            let loopMetadata = OllamaProxyRequestParser.metadata(
                path: "/api/generate",
                body: Data(#"{"model":"model-\#(index)","prompt":"hidden"}"#.utf8)
            )
            proxy.recordDiagnostic(
                metadata: loopMetadata,
                startedAt: startedAt.addingTimeInterval(Double(index)),
                endedAt: startedAt.addingTimeInterval(Double(index + 1)),
                upstreamStatusCode: 200,
                proxyError: nil,
                guardrailDecision: .allowed
            )
        }

        XCTAssertEqual(proxy.diagnosticRecords.count, 50)
        XCTAssertEqual(proxy.diagnosticRecords.first?.model, "model-5")

        proxy.clearDiagnostics()
        XCTAssertTrue(proxy.diagnosticRecords.isEmpty)
    }

    func testProxyDiagnosticRecordsSummarizeGuardrailBlocksWithoutPromptText() {
        let proxy = OllamaProxyServer()
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let metadata = OllamaProxyRequestParser.metadata(
            path: "/v1/chat/completions",
            body: Data(#"{"model":"qwen3:latest","messages":[{"role":"user","content":"secret huge prompt"}],"num_ctx":4}"#.utf8)
        )
        let decision = PromptGuardrailPolicy.defaults.evaluate(metadata)

        proxy.recordDiagnostic(
            metadata: metadata,
            startedAt: startedAt,
            endedAt: startedAt,
            upstreamStatusCode: nil,
            proxyError: nil,
            guardrailDecision: decision
        )

        XCTAssertEqual(proxy.diagnosticRecords[0].guardrailOutcome, .blocked)
        XCTAssertNil(proxy.diagnosticRecords[0].upstreamStatusCode)
        XCTAssertTrue(proxy.diagnosticsSummary().contains("guardrail blocked"))
        XCTAssertFalse(proxy.diagnosticsSummary().contains("secret huge prompt"))
    }
}
