import XCTest
@testable import OllamaDashboard

final class ModelParsingTests: XCTestCase {
    func testDecodesInstalledModelsWithMissingFields() throws {
        let data = Fixtures.data("tags")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds

        let response = try decoder.decode(InstalledModelsResponse.self, from: data)

        XCTAssertEqual(response.models.count, 2)
        XCTAssertEqual(response.models[0].name, "llama3.2:latest")
        XCTAssertEqual(response.models[0].details?.parameterSize, "3.2B")
        XCTAssertNil(response.models[1].details)
    }

    func testDecodesRunningModelsWithUnknownOptionalFields() throws {
        let data = Fixtures.data("ps")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds

        let response = try decoder.decode(RunningModelsResponse.self, from: data)

        XCTAssertEqual(response.models.first?.name, "qwen2.5-coder:7b")
        XCTAssertEqual(response.models.first?.sizeVRAM, 123456789)
    }

    func testBenchmarkCalculatesTokensPerSecondAndWarmInference() throws {
        let data = Fixtures.data("generate")
        let chunk = try JSONDecoder().decode(GenerateResponseChunk.self, from: data)
        let result = BenchmarkResult(
            model: "llama3.2",
            prompt: "hello",
            response: chunk.response ?? "",
            totalDuration: chunk.totalDuration,
            loadDuration: chunk.loadDuration,
            promptEvalCount: chunk.promptEvalCount,
            promptEvalDuration: chunk.promptEvalDuration,
            evalCount: chunk.evalCount,
            evalDuration: chunk.evalDuration
        )

        XCTAssertEqual(result.outputTokensPerSecond ?? 0, 25, accuracy: 0.01)
        XCTAssertTrue(result.wasAlreadyWarm)
    }
}
