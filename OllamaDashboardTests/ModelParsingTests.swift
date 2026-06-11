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
        XCTAssertEqual(response.models.first?.contextLength, 4096)
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

    func testModelContextMetadataExtractsContextLengthFromModelInfo() {
        let detail = ModelDetail(
            license: nil,
            modelfile: nil,
            parameters: nil,
            template: nil,
            details: nil,
            modelInfo: [
                "gemma4.context_length": .number(131_072),
                "general.architecture": .string("gemma4")
            ]
        )

        let metadata = ModelContextMetadata(detail: detail)

        XCTAssertEqual(metadata.maxContextLength, 131_072)
    }

    func testModelGenerationParametersParseNumericSuggestions() {
        let parameters = """
        temperature 0.65
        top_p 0.9
        top_k 40
        repeat_penalty 1.1
        repeat_last_n 128
        mirostat 2
        mirostat_tau 5.0
        mirostat_eta 0.1
        seed 42
        num_predict 2048
        stop "<end>"
        """

        let options = ProfileGenerationOptions(modelParameters: parameters)

        XCTAssertEqual(options.temperature, 0.65)
        XCTAssertEqual(options.topP, 0.9)
        XCTAssertEqual(options.topK, 40)
        XCTAssertEqual(options.repeatPenalty, 1.1)
        XCTAssertEqual(options.repeatLastN, 128)
        XCTAssertEqual(options.mirostat, 2)
        XCTAssertEqual(options.mirostatTau, 5.0)
        XCTAssertEqual(options.mirostatEta, 0.1)
        XCTAssertEqual(options.seed, 42)
        XCTAssertEqual(options.numPredict, 2048)
    }
}
