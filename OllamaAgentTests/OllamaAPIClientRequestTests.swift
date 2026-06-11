import XCTest
@testable import OllamaAgent

final class OllamaAPIClientRequestTests: XCTestCase {
    private var client: OllamaAPIClient!
    private var session: StubHTTPSession!

    override func setUp() {
        super.setUp()
        session = StubHTTPSession()
        client = OllamaAPIClient(baseURL: URL(string: "http://ollama.test")!, session: session)
    }

    override func tearDown() {
        client = nil
        session = nil
        super.tearDown()
    }

    func testGetVersionSendsExpectedRequestAndDecodesResponse() async throws {
        await session.setStub(.init(data: #"{"version":"0.9.1"}"#.data(using: .utf8)!), for: "/api/version")

        let version = try await client.getVersion()

        XCTAssertEqual(version.version, "0.9.1")
        let requests = await session.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/version")
    }

    func testGetInstalledAndRunningModelsDecodeResponses() async throws {
        await session.setStub(.init(data: Fixtures.data("tags")), for: "/api/tags")
        await session.setStub(.init(data: Fixtures.data("ps")), for: "/api/ps")

        let installed = try await client.getInstalledModels()
        let running = try await client.getRunningModels()

        XCTAssertEqual(installed.map(\.name), ["llama3.2:latest", "tinyllama:latest"])
        XCTAssertEqual(running.map(\.name), ["qwen2.5-coder:7b"])
        let requests = await session.capturedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/tags", "/api/ps"])
    }

    func testShowModelRejectsInvalidModelNameBeforeSendingRequest() async {
        do {
            _ = try await client.showModel(name: "llama; rm -rf /")
            XCTFail("Expected invalid model name error")
        } catch {
            XCTAssertEqual(error as? OllamaAPIError, .invalidModelName)
            let requests = await session.capturedRequests()
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testShowModelSendsModelBody() async throws {
        await session.setStub(
            .init(data: #"{"license":"MIT","modelfile":"FROM llama3.2"}"#.data(using: .utf8)!),
            for: "/api/show"
        )

        let detail = try await client.showModel(name: "llama3.2:latest")

        XCTAssertEqual(detail.license, "MIT")
        let requests = await session.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(body["model"] as? String, "llama3.2:latest")
    }

    func testWarmModelSendsGenerateBodyAndRemovesPredictionLimit() async throws {
        await session.setStub(.init(data: Fixtures.data("generate")), for: "/api/generate")

        let result = try await client.warmModel(
            name: "qwen2.5-coder:7b",
            keepAlive: "1h",
            numCtx: 32_768,
            options: [
                "temperature": .number(0.2),
                "num_predict": .number(2048)
            ]
        )

        XCTAssertEqual(result, WarmModelResult(model: "qwen2.5-coder:7b", keepAlive: "1h", loaded: true))
        let requests = await session.capturedRequests()
        let body = try XCTUnwrap(requests.first?.jsonBody)
        XCTAssertEqual(body["model"] as? String, "qwen2.5-coder:7b")
        XCTAssertEqual(body["prompt"] as? String, "")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["keep_alive"] as? String, "1h")
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Double, 0.2)
        XCTAssertEqual(options["num_ctx"] as? Double, 32_768)
        XCTAssertNil(options["num_predict"])
    }

    func testUnloadModelSendsKeepAliveZero() async throws {
        await session.setStub(.init(data: Fixtures.data("generate")), for: "/api/generate")

        let result = try await client.unloadModelViaAPI(name: "llama3.2:latest")

        XCTAssertEqual(result.method, "API keep_alive=0")
        let requests = await session.capturedRequests()
        let body = try XCTUnwrap(requests.first?.jsonBody)
        XCTAssertEqual(body["keep_alive"] as? String, "0")
        XCTAssertEqual(body["prompt"] as? String, "")
    }

    func testRunBenchmarkSendsPromptAndMapsTimingFields() async throws {
        await session.setStub(.init(data: Fixtures.data("generate")), for: "/api/generate")

        let result = try await client.runBenchmark(
            model: "llama3.2:latest",
            prompt: "hello",
            numCtx: 4096,
            keepAlive: "5m",
            options: ["temperature": .number(0.4)]
        )

        XCTAssertEqual(result.prompt, "hello")
        XCTAssertEqual(result.response, "Done.")
        XCTAssertEqual(try XCTUnwrap(result.outputTokensPerSecond), 25, accuracy: 0.01)
        let requests = await session.capturedRequests()
        let body = try XCTUnwrap(requests.first?.jsonBody)
        XCTAssertEqual(body["prompt"] as? String, "hello")
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        XCTAssertEqual(options["num_ctx"] as? Double, 4096)
        XCTAssertEqual(options["temperature"] as? Double, 0.4)
    }

    func testGenerateBenchmarkUsesLongerRequestTimeoutThanWarmAndUnload() async throws {
        await session.setStub(.init(data: Fixtures.data("generate")), for: "/api/generate")

        _ = try await client.warmModel(name: "llama3.2:latest", keepAlive: "5m", numCtx: nil, options: [:])
        _ = try await client.runBenchmark(model: "llama3.2:latest", prompt: "hello", numCtx: nil, keepAlive: "5m", options: [:])
        _ = try await client.unloadModelViaAPI(name: "llama3.2:latest")

        let requests = await session.capturedRequests()
        XCTAssertEqual(requests.map(\.timeoutInterval), [30, 300, 30])
    }

    func testBadStatusAndEmptyResponseSurfaceTypedErrors() async throws {
        await session.setStub(.init(statusCode: 503, data: Data()), for: "/api/version")
        do {
            _ = try await client.getVersion()
            XCTFail("Expected bad status")
        } catch {
            XCTAssertEqual(error as? OllamaAPIError, .badStatus(503))
        }

        session = StubHTTPSession()
        client = OllamaAPIClient(baseURL: URL(string: "http://ollama.test")!, session: session)
        await session.setStub(.init(statusCode: 200, data: Data()), for: "/api/version")
        do {
            _ = try await client.getVersion()
            XCTFail("Expected empty response")
        } catch {
            XCTAssertEqual(error as? OllamaAPIError, .emptyResponse)
        }
    }
}

private extension URLRequest {
    var jsonBody: [String: Any]? {
        guard let httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
    }
}
