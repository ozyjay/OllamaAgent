import XCTest
@testable import OllamaAgent

final class InstalledModelPolicyTests: XCTestCase {
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

    func testModelWarmRequestUsesSelectedModelWhenProfileIsMissing() {
        let request = ModelWarmRequest.resolve(
            selectedModelName: "llama3.2:latest",
            profile: nil,
            modelMaxContext: nil
        )

        XCTAssertEqual(request.model, "llama3.2:latest")
        XCTAssertEqual(request.keepAlive, "30m")
        XCTAssertNil(request.numCtx)
        XCTAssertEqual(request.options, [:])
        XCTAssertEqual(request.statusDetail, "keep_alive 30m, model default context.")
    }

    func testModelWarmRequestAppliesProfileSettingsToSelectedInstalledModelWarmUp() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Coding",
            preferredModel: "different-model:latest",
            contextPolicy: .balanced,
            contextOverrides: [],
            keepAlive: "1h",
            numPredict: 4096,
            temperature: 0.2,
            generationOptions: ProfileGenerationOptions(
                temperature: 0.4,
                numPredict: 1024
            ),
            notes: "",
            purpose: "Stable coding assistant"
        )

        let request = ModelWarmRequest.resolve(
            selectedModelName: "qwen2.5-coder:7b",
            profile: profile,
            modelMaxContext: 65_536
        )

        XCTAssertEqual(request.model, "qwen2.5-coder:7b")
        XCTAssertEqual(request.keepAlive, "1h")
        XCTAssertEqual(request.numCtx, 32_768)
        XCTAssertEqual(request.options["temperature"], .number(0.4))
        XCTAssertEqual(request.options["num_predict"], .number(1024))
        XCTAssertEqual(request.statusDetail, "keep_alive 1h, num_ctx 32768 from profile policy.")
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

    func testModelStatusPolicyMarksInstalledModelsWarmWhenLoaded() {
        let now = Date(timeIntervalSince1970: 1_000)
        let installed = [
            makeInstalledModel(name: "llama3.2:latest"),
            makeInstalledModel(name: "qwen2.5-coder:7b")
        ]
        let running = [makeRunningModel(name: "qwen2.5-coder:7b", expiresAt: now.addingTimeInterval(125))]

        XCTAssertEqual(
            ModelStatusPolicy.statusRows(installedModels: installed, runningModels: running, now: now),
            [
                ModelStatusRow(modelName: "llama3.2:latest", status: .idle, timeRemaining: nil),
                ModelStatusRow(modelName: "qwen2.5-coder:7b", status: .warm, timeRemaining: "2m 5s")
            ]
        )
    }

    func testModelStatusPolicyTreatsExpiredRunningModelsAsIdle() {
        let now = Date(timeIntervalSince1970: 1_000)
        let installed = [makeInstalledModel(name: "llama3.2:latest")]
        let running = [makeRunningModel(name: "llama3.2:latest", expiresAt: now.addingTimeInterval(-1))]

        XCTAssertEqual(
            ModelStatusPolicy.statusRows(installedModels: installed, runningModels: running, now: now),
            [
                ModelStatusRow(modelName: "llama3.2:latest", status: .idle, timeRemaining: nil)
            ]
        )
    }

    func testInstalledModelActionPolicyDisablesWarmWhenModelIsAlreadyLoaded() {
        XCTAssertFalse(InstalledModelActionPolicy.canWarmSelected(status: nil, isWarming: false))
        XCTAssertFalse(InstalledModelActionPolicy.canWarmSelected(status: .warm, isWarming: false))
        XCTAssertFalse(InstalledModelActionPolicy.canWarmSelected(status: .busy, isWarming: false))
        XCTAssertFalse(InstalledModelActionPolicy.canWarmSelected(status: .idle, isWarming: true))
        XCTAssertFalse(InstalledModelActionPolicy.canWarmSelected(status: .idle, isWarming: false, isUnloading: true))
        XCTAssertTrue(InstalledModelActionPolicy.canWarmSelected(status: .idle, isWarming: false))

        XCTAssertFalse(InstalledModelActionPolicy.canUnloadSelected(isWarm: false, isWarming: false, isUnloading: false))
        XCTAssertFalse(InstalledModelActionPolicy.canUnloadSelected(isWarm: true, isWarming: true, isUnloading: false))
        XCTAssertFalse(InstalledModelActionPolicy.canUnloadSelected(isWarm: true, isWarming: false, isUnloading: true))
        XCTAssertTrue(InstalledModelActionPolicy.canUnloadSelected(isWarm: true, isWarming: false, isUnloading: false))

        XCTAssertFalse(InstalledModelActionPolicy.canUseSelectionActions(hasSelection: false, isWarming: false, isUnloading: false))
        XCTAssertFalse(InstalledModelActionPolicy.canUseSelectionActions(hasSelection: true, isWarming: true, isUnloading: false))
        XCTAssertFalse(InstalledModelActionPolicy.canUseSelectionActions(hasSelection: true, isWarming: false, isUnloading: true))
        XCTAssertTrue(InstalledModelActionPolicy.canUseSelectionActions(hasSelection: true, isWarming: false, isUnloading: false))
    }

    func testModelLifecycleTransitionPolicyWaitsForObservedStatusChanges() {
        let now = Date(timeIntervalSince1970: 1_000)
        let installed = [makeInstalledModel(name: "llama3.2:latest")]
        let warmRunning = [makeRunningModel(name: "llama3.2", expiresAt: now.addingTimeInterval(60))]
        let expiredRunning = [makeRunningModel(name: "llama3.2", expiresAt: now.addingTimeInterval(-1))]

        XCTAssertTrue(ModelLifecycleTransitionPolicy.installedModelReached(
            modelName: "llama3.2:latest",
            targetStatus: .warm,
            installedModels: installed,
            runningModels: warmRunning,
            activeModelNames: [],
            now: now
        ))
        XCTAssertFalse(ModelLifecycleTransitionPolicy.installedModelReached(
            modelName: "llama3.2:latest",
            targetStatus: .idle,
            installedModels: installed,
            runningModels: warmRunning,
            activeModelNames: [],
            now: now
        ))
        XCTAssertTrue(ModelLifecycleTransitionPolicy.installedModelReached(
            modelName: "llama3.2:latest",
            targetStatus: .idle,
            installedModels: installed,
            runningModels: expiredRunning,
            activeModelNames: [],
            now: now
        ))
        XCTAssertFalse(ModelLifecycleTransitionPolicy.runningModelIsAbsent(
            modelName: "llama3.2:latest",
            runningModels: warmRunning,
            now: now
        ))
        XCTAssertTrue(ModelLifecycleTransitionPolicy.runningModelIsAbsent(
            modelName: "llama3.2:latest",
            runningModels: expiredRunning,
            now: now
        ))
    }

    func testPreferredModelSelectionPolicySelectsProfilePreferredInstalledModel() {
        let installed = [
            makeInstalledModel(name: "llama3.2:latest"),
            makeInstalledModel(name: "qwen3:27b")
        ]
        var profile = RuntimeProfile.builtIns[0]
        profile.preferredModel = "llama3.2"

        XCTAssertEqual(
            PreferredModelSelectionPolicy.selectedInstalledModelID(for: profile, installedModels: installed),
            installed[0].id
        )

        profile.preferredModel = "missing:latest"
        XCTAssertNil(PreferredModelSelectionPolicy.selectedInstalledModelID(for: profile, installedModels: installed))
        XCTAssertNil(PreferredModelSelectionPolicy.selectedInstalledModelID(for: nil, installedModels: installed))
    }

    func testWarmTimeRemainingFormatterUsesCompactUnits() {
        XCTAssertEqual(WarmTimeRemainingFormatter.string(from: 45), "45s")
        XCTAssertEqual(WarmTimeRemainingFormatter.string(from: 120), "2m")
        XCTAssertEqual(WarmTimeRemainingFormatter.string(from: 125), "2m 5s")
        XCTAssertEqual(WarmTimeRemainingFormatter.string(from: 3_900), "1h 5m")
        XCTAssertEqual(WarmTimeRemainingFormatter.string(from: -10), "0s")
    }

    func testModelStatusPolicyMarksProxyActiveModelsBusy() {
        let installed = [makeInstalledModel(name: "qwen2.5-coder:7b")]
        let running = [makeRunningModel(name: "qwen2.5-coder:7b")]

        XCTAssertEqual(
            ModelStatusPolicy.statusRows(
                installedModels: installed,
                runningModels: running,
                activeModelNames: ["qwen2.5-coder:7b"]
            ),
            [
                ModelStatusRow(modelName: "qwen2.5-coder:7b", status: .busy, timeRemaining: nil)
            ]
        )
    }

    func testModelStatusPolicyMatchesLatestAliasesForProxyActivity() {
        let installed = [makeInstalledModel(name: "qwen3:latest")]
        let running = [makeRunningModel(name: "qwen3:latest")]

        XCTAssertEqual(
            ModelStatusPolicy.statusRows(
                installedModels: installed,
                runningModels: running,
                activeModelNames: ["qwen3"]
            ),
            [
                ModelStatusRow(modelName: "qwen3:latest", status: .busy, timeRemaining: nil)
            ]
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

    func testInstalledModelRowSummaryInfersParameterSizeFromModelNameWhenMetadataIsMissing() {
        let model = InstalledModel(
            name: "qwen3.6:27b-mlx",
            modifiedAt: nil,
            size: 19_760_000_000,
            digest: "60b0437bbd02abcdef",
            details: nil
        )

        let summary = InstalledModelRowSummary(model: model)

        XCTAssertEqual(summary.trailingPrimary, "27B")
        XCTAssertEqual(summary.trailingSecondary, "19.76 GB")
        XCTAssertEqual(summary.metadata, "60b0437bbd02")
    }

    func testModelDetailSummaryUsesHumanReadableFields() {
        let detail = ModelDetail(
            license: "MIT",
            modelfile: "FROM llama3.2",
            parameters: "num_ctx 4096",
            template: nil,
            details: ModelDetails(
                parentModel: nil,
                format: "gguf",
                family: "llama",
                families: ["llama"],
                parameterSize: "3.2B",
                quantizationLevel: "Q4_K_M"
            ),
            modelInfo: ["general.architecture": .string("llama")]
        )

        let summary = ModelDetailSummary(detail: detail)

        XCTAssertEqual(summary.fields.map(\.label), ["Format", "Family", "Parameters", "Quantization", "License"])
        XCTAssertEqual(summary.fields.map(\.value), ["gguf", "llama", "3.2B", "Q4_K_M", "MIT"])
        XCTAssertEqual(summary.sections.map(\.title), ["Modelfile", "Parameters"])
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

    func testInstalledModelDetailToggleHidesOnlyVisibleSelectedDetails() {
        XCTAssertTrue(
            InstalledModelDetailToggle.shouldHideDetails(
                selectedModelID: "gemma4:12b",
                detailModelID: "gemma4:12b",
                hasDetailSummary: true,
                targetModelID: "gemma4:12b"
            )
        )
        XCTAssertFalse(
            InstalledModelDetailToggle.shouldHideDetails(
                selectedModelID: "gemma4:12b",
                detailModelID: "gemma4:12b",
                hasDetailSummary: true,
                targetModelID: "qwen3.6:27b-mlx"
            )
        )
        XCTAssertFalse(
            InstalledModelDetailToggle.shouldHideDetails(
                selectedModelID: "gemma4:12b",
                detailModelID: "gemma4:12b",
                hasDetailSummary: false,
                targetModelID: "gemma4:12b"
            )
        )
    }
}
