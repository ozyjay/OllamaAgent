import XCTest
@testable import OllamaAgent

final class FormattingAndViewPolicyTests: XCTestCase {
    func testFormattersAndJSONIntegerValueEdgeCases() {
        XCTAssertEqual(ByteFormatter.string(from: nil), "Unknown")
        XCTAssertTrue(ByteFormatter.string(from: 1_500_000).contains("MB"))
        XCTAssertEqual(DurationFormatter.nanoseconds(nil), "Unknown")
        XCTAssertEqual(DurationFormatter.nanoseconds(250_000_000), "250 ms")
        XCTAssertEqual(DurationFormatter.nanoseconds(1_500_000_000), "1.50 s")

        XCTAssertEqual(JSONValue.number(42.9).integerValue, 42)
        XCTAssertEqual(JSONValue.string(" 4096 ").integerValue, 4096)
        XCTAssertNil(JSONValue.string("nope").integerValue)
        XCTAssertNil(JSONValue.bool(true).integerValue)
    }

    func testBenchmarkEdgeCasesAndPromptLabels() {
        let zeroDuration = BenchmarkResult(
            model: "m",
            prompt: "p",
            response: "",
            totalDuration: nil,
            loadDuration: 50_000_000,
            promptEvalCount: nil,
            promptEvalDuration: nil,
            evalCount: 10,
            evalDuration: 0
        )

        XCTAssertNil(zeroDuration.outputTokensPerSecond)
        XCTAssertFalse(zeroDuration.wasAlreadyWarm)
        XCTAssertEqual(BenchmarkPrompt.allCases.map(\.label), ["Tiny", "Coding", "Reasoning", "Custom"])
        XCTAssertEqual(BenchmarkPrompt.custom.prompt, "")
    }

    func testLogTailHelperHandlesEmptyAndMaximumLines() {
        XCTAssertEqual(OllamaLogTail.tail("", maxLines: 200), "")
        XCTAssertEqual(OllamaLogTail.tail("one\ntwo\nthree", maxLines: 2), "two\nthree")
        XCTAssertEqual(OllamaLogTail.tail("one\ntwo", maxLines: 10), "one\ntwo")
        XCTAssertEqual(OllamaLogTail.newestFirst("one\ntwo\nthree"), "three\ntwo\none")
        XCTAssertEqual(OllamaLogTail.newestFirst(""), "")
    }

    func testLogTailHelperDropsPartialFirstLineWhenByteReadWasTruncated() {
        let data = Data("partial line\ncomplete one\ncomplete two\ncomplete three".utf8)

        XCTAssertEqual(
            OllamaLogTail.tail(data, wasTruncated: true, maxLines: 2),
            "complete two\ncomplete three"
        )
        XCTAssertEqual(
            OllamaLogTail.tail(data, wasTruncated: false, maxLines: 2),
            "complete two\ncomplete three"
        )
        XCTAssertEqual(
            OllamaLogTail.tail(Data("partial only".utf8), wasTruncated: true, maxLines: 2),
            ""
        )
    }

    func testLogClassifierCategoriesAndFiltering() {
        XCTAssertTrue(
            OllamaLogClassifier.categories(for: #"level=ERROR msg="runner exited: out of memory""#)
                .contains(.errors)
        )
        XCTAssertTrue(
            OllamaLogClassifier.categories(for: #"POST /api/generate model=qwen3:latest status=200"#)
                .contains(.requests)
        )
        XCTAssertTrue(
            OllamaLogClassifier.categories(for: #"msg="loading model" model_path=/models/gemma.gguf"#)
                .contains(.modelLoad)
        )

        let text = """
        level=ERROR msg="runner exited"
        POST /api/generate model=qwen3
        msg="loading model"
        """

        XCTAssertEqual(
            OllamaLogClassifier.filteredLines(in: text, selectedCategories: [.errors], searchText: ""),
            #"level=ERROR msg="runner exited""#
        )
        XCTAssertEqual(
            OllamaLogClassifier.filteredLines(in: text, selectedCategories: [.requests], searchText: "qwen3"),
            "POST /api/generate model=qwen3"
        )
    }

    func testLogClassifierBuildsHumanReadableEntries() {
        let text = """
        time=2026-06-10T10:00:00 level=ERROR msg="runner exited: out of memory"
        POST /api/generate model=qwen3:latest status=200
        level=INFO msg="loading model" model=gemma4:12b
        """

        let entries = OllamaLogClassifier.entries(in: text, selectedCategories: [], searchText: "")

        XCTAssertEqual(entries.map(\.severity), [.error, .request, .model])
        XCTAssertEqual(entries[0].summary, "Error: runner exited: out of memory")
        XCTAssertEqual(entries[1].summary, "Request /api/generate for qwen3:latest returned 200")
        XCTAssertEqual(entries[2].summary, "Model gemma4:12b: loading model")
    }

    func testSystemResourceParserReadsTopCPUUsage() throws {
        let output = """
        Processes: 488 total, 3 running, 485 sleeping
        CPU usage: 12.3% user, 4.7% sys, 83.0% idle
        """

        let usage = try XCTUnwrap(SystemResourceParser.cpuUsage(from: output))

        XCTAssertEqual(usage.userPercent, 12.3, accuracy: 0.001)
        XCTAssertEqual(usage.systemPercent, 4.7, accuracy: 0.001)
        XCTAssertEqual(usage.idlePercent, 83.0, accuracy: 0.001)
        XCTAssertEqual(usage.busyPercent, 17.0, accuracy: 0.001)
    }

    func testSystemResourceParserReadsOllamaGPUMemoryAndPeak() throws {
        let text = """
        time=2026-06-11T10:00:00 level=INFO msg="gpu memory" id=0 library=Metal available="51.3 GiB" free="51.8 GiB" minimum="512.0 MiB" overhead="0 B"
        time=2026-06-11T10:01:00 level=INFO msg="load tensors" size="25.10 GiB" peak memory="25.10 GiB"
        """

        let status = try XCTUnwrap(SystemResourceParser.gpuStatus(from: text))

        XCTAssertEqual(status.availableBytes, 55_082_955_571)
        XCTAssertEqual(status.freeBytes, 55_619_826_483)
        XCTAssertEqual(status.peakBytes, 26_950_919_782)
        XCTAssertEqual(try XCTUnwrap(status.usageFraction), 0.4893, accuracy: 0.001)
    }

    func testSystemResourceParserFallsBackToGPUMemoryPressureWhenPeakIsMissing() throws {
        let text = #"level=INFO msg="gpu memory" id=0 library=Metal available="20 GiB" free="5 GiB""#

        let status = try XCTUnwrap(SystemResourceParser.gpuStatus(from: text))

        XCTAssertEqual(try XCTUnwrap(status.usageFraction), 0.75, accuracy: 0.001)
    }

    func testCLIRejectsInvalidModelNameBeforeExecutableLookup() async {
        let client = OllamaCLIClient(executablePath: "/definitely/not/ollama")

        do {
            try await client.stopModel(name: "bad;model")
            XCTFail("Expected invalid model error")
        } catch {
            XCTAssertEqual(error as? CLIError, .invalidModelName)
        }
    }
}
