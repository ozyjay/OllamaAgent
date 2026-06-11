import XCTest
@testable import OllamaDashboard

final class FormattingAndViewPolicyTests: XCTestCase {
    func testModelWarmRequestCoversPreferredModelDefaultContextOverrideAndClamping() {
        let preferred = RuntimeProfile(
            id: UUID(),
            name: "Preferred",
            preferredModel: "qwen2.5-coder:7b",
            contextPolicy: .modelDefault,
            contextOverrides: [],
            keepAlive: "-1",
            numPredict: 2048,
            temperature: 0.2,
            notes: "",
            purpose: "Preferred model"
        )
        let preferredRequest = ModelWarmRequest.resolve(
            selectedModelName: "llama3.2:latest",
            profile: preferred,
            modelMaxContext: nil
        )
        XCTAssertEqual(preferredRequest.model, "llama3.2:latest")
        XCTAssertEqual(preferredRequest.statusDetail, "keep_alive -1, model default context.")

        let customKeepAlive = ModelWarmRequest.resolve(
            selectedModelName: "llama3.2:latest",
            profile: nil,
            modelMaxContext: nil,
            defaultKeepAlive: "5m"
        )
        XCTAssertEqual(customKeepAlive.keepAlive, "5m")
        XCTAssertEqual(customKeepAlive.statusDetail, "keep_alive 5m, model default context.")

        let override = RuntimeProfile(
            id: UUID(),
            name: "Override",
            preferredModel: "",
            contextPolicy: .lowRAM,
            contextOverrides: [ModelContextOverride(model: "llama3.2:latest", numCtx: 65_536)],
            keepAlive: "30m",
            numPredict: 2048,
            temperature: 0.2,
            notes: "",
            purpose: "Override"
        )
        let clamped = ModelWarmRequest.resolve(
            selectedModelName: "llama3.2:latest",
            profile: override,
            modelMaxContext: 8192
        )
        XCTAssertEqual(clamped.numCtx, 8192)
        XCTAssertEqual(clamped.statusDetail, "keep_alive 30m, num_ctx 8192 from per-model override, clamped to model maximum.")
    }

    func testInstalledModelFilteringAndSorting() {
        let oldDate = Date(timeIntervalSince1970: 10)
        let newDate = Date(timeIntervalSince1970: 20)
        let models = [
            makeInstalledModel(name: "zeta:7b", modifiedAt: oldDate, size: 10),
            makeInstalledModel(name: "alpha:3b", modifiedAt: newDate, size: 30),
            makeInstalledModel(name: "beta:1b", modifiedAt: nil, size: 20)
        ]

        XCTAssertEqual(
            InstalledModelListPolicy.filteredModels(models, searchText: "", sort: .name).map(\.name),
            ["alpha:3b", "beta:1b", "zeta:7b"]
        )
        XCTAssertEqual(
            InstalledModelListPolicy.filteredModels(models, searchText: "TA", sort: .name).map(\.name),
            ["beta:1b", "zeta:7b"]
        )
        XCTAssertEqual(
            InstalledModelListPolicy.filteredModels(models, searchText: "", sort: .size).map(\.name),
            ["alpha:3b", "beta:1b", "zeta:7b"]
        )
        XCTAssertEqual(
            InstalledModelListPolicy.filteredModels(models, searchText: "", sort: .modified).map(\.name),
            ["alpha:3b", "zeta:7b", "beta:1b"]
        )
    }

    func testModelRowNameSizingUsesContentThenYieldsToMinimumFieldArea() {
        let roomy = ModelRowNameSizing.widths(
            availableWidth: 600,
            idealNameWidth: 160,
            minimumFieldsWidth: 210,
            spacing: 12
        )
        XCTAssertEqual(roomy.nameWidth, 160)
        XCTAssertEqual(roomy.fieldsWidth, 428)

        let constrained = ModelRowNameSizing.widths(
            availableWidth: 360,
            idealNameWidth: 320,
            minimumFieldsWidth: 210,
            spacing: 12
        )
        XCTAssertEqual(constrained.nameWidth, 138)
        XCTAssertEqual(constrained.fieldsWidth, 210)
    }

    func testModelNameWidthPolicyUsesLongestVisibleModelName() {
        let models = [
            makeInstalledModel(name: "tiny:1b"),
            makeInstalledModel(name: "qwen2.5-coder:32b-instruct-q8")
        ]

        let width = ModelNameWidthPolicy.preferredNameWidth(
            for: models,
            measuring: { CGFloat($0.count * 10) }
        )

        XCTAssertEqual(width, 290)
    }

    func testModelProfileUsageRecordsProfileUsedForSelectedWarmTarget() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Long Context",
            preferredModel: "qwen2.5-coder:7b",
            contextPolicy: .maxKnown,
            contextOverrides: [],
            keepAlive: "1h",
            numPredict: 2048,
            temperature: 0.2,
            notes: "",
            purpose: "Large prompts"
        )

        var usage = ModelProfileUsage()
        usage.record(profile: profile, fallbackModel: "llama3.2:latest")
        XCTAssertEqual(usage.profileName(for: "llama3.2:latest"), "Long Context")
        XCTAssertNil(usage.profileName(for: "qwen2.5-coder:7b"))

        usage.record(profile: nil, fallbackModel: "llama3.2:latest")
        XCTAssertEqual(usage.profileName(for: "llama3.2:latest"), "No profile")
    }

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

    func testModelDetailSummaryAndParameterInferenceEdgeCases() {
        XCTAssertNil(ParameterSizeInference.value(from: "model-without-size"))
        XCTAssertEqual(ParameterSizeInference.value(from: "repo/qwen:0.5b"), "0.5B")

        let detail = ModelDetail(
            license: "\n",
            modelfile: nil,
            parameters: "temperature 0.2",
            template: "template",
            details: ModelDetails(
                parentModel: nil,
                format: nil,
                family: nil,
                families: ["gemma", "bert"],
                parameterSize: nil,
                quantizationLevel: nil
            ),
            modelInfo: nil
        )
        let summary = ModelDetailSummary(detail: detail)

        XCTAssertEqual(summary.fields.map(\.label), ["Family", "Temperature"])
        XCTAssertEqual(summary.fields.map(\.value), ["gemma, bert", "0.2"])
        XCTAssertEqual(summary.sections.map(\.title), ["Parameters", "Template"])
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
