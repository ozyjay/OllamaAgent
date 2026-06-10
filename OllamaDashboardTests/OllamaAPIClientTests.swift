import XCTest
@testable import OllamaDashboard

@MainActor
final class OllamaAPIClientTests: XCTestCase {
    func testModelNameValidatorRejectsShellMetacharacters() {
        XCTAssertTrue(ModelNameValidator.isValid("qwen2.5-coder:7b"))
        XCTAssertTrue(ModelNameValidator.isValid("registry.example/ns/model:tag"))
        XCTAssertFalse(ModelNameValidator.isValid("llama; rm -rf /"))
        XCTAssertFalse(ModelNameValidator.isValid(""))
    }

    func testProfileManagerSeedsBuiltInsAndSavesJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("profiles.json")

        let manager = ProfileManager(fileURL: fileURL)
        XCTAssertEqual(manager.profiles.map(\.name), ["Coding - Conservative", "Long Context", "Low RAM"])
        XCTAssertEqual(manager.profiles.map(\.contextPolicy), [.balanced, .maxKnown, .lowRAM])

        manager.profiles[0].preferredModel = "llama3.2:latest"
        manager.profiles[0].contextPolicy = .maxKnown
        manager.profiles[0].contextOverrides = [
            ModelContextOverride(model: "llama3.2:latest", numCtx: 8192)
        ]
        manager.profiles[0].generationOptions.topP = 0.85
        manager.profiles[0].generationOptions.topK = 50
        try manager.save()

        let reloaded = ProfileManager(fileURL: fileURL)
        XCTAssertEqual(reloaded.profiles[0].preferredModel, "llama3.2:latest")
        XCTAssertEqual(reloaded.profiles[0].contextPolicy, .maxKnown)
        XCTAssertEqual(reloaded.profiles[0].contextOverrides.first?.model, "llama3.2:latest")
        XCTAssertEqual(reloaded.profiles[0].contextOverrides.first?.numCtx, 8192)
        XCTAssertEqual(reloaded.profiles[0].generationOptions.topP, 0.85)
        XCTAssertEqual(reloaded.profiles[0].generationOptions.topK, 50)
    }

    func testRuntimeProfileDecodesLegacyNumCtxIntoClosestPolicy() throws {
        let data = """
        [{
          "id": "44444444-4444-4444-4444-444444444444",
          "name": "Legacy Long",
          "preferredModel": "",
          "numCtx": 65536,
          "keepAlive": "30m",
          "numPredict": 4096,
          "temperature": 0.2,
          "notes": "",
          "purpose": "Legacy profile"
        }]
        """.data(using: .utf8)!

        let profiles = try JSONDecoder().decode([RuntimeProfile].self, from: data)

        XCTAssertEqual(profiles.first?.contextPolicy, .maxKnown)
        XCTAssertEqual(profiles.first?.contextOverrides, [])
    }

    func testSettingsDefaults() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: suite)

        XCTAssertEqual(settings.baseURLString, "http://localhost:11434")
        XCTAssertEqual(settings.refreshInterval, .manual)
        XCTAssertFalse(settings.enableCLIControls)
        XCTAssertFalse(settings.enableProxy)
        XCTAssertEqual(settings.proxyPort, 11_435)
        XCTAssertTrue(settings.confirmUnload)
    }

    func testDashboardTabsUseCoreMoreOrder() {
        XCTAssertEqual(DashboardTab.allCases.map(\.rawValue), [
            "Logs",
            "Profiles",
            "Models",
            "Settings"
        ])
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

    func testPendingUnloadConfirmationKeepsSelectedModelNameUntilConfirmed() {
        let selected = RunningModel(
            name: "qwen2.5-coder:7b",
            model: nil,
            size: nil,
            digest: nil,
            details: nil,
            expiresAt: nil,
            sizeVRAM: nil,
            contextLength: nil
        )
        var confirmation = PendingUnloadConfirmation()

        confirmation.begin(for: selected)

        XCTAssertTrue(confirmation.isPresented)
        XCTAssertEqual(confirmation.confirm(), "qwen2.5-coder:7b")
        XCTAssertFalse(confirmation.isPresented)
    }

    func testRuntimeProfileApplicationKeepsCurrentModelWhenPreferredModelIsBlank() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Low RAM",
            preferredModel: "",
            contextPolicy: .lowRAM,
            contextOverrides: [],
            keepAlive: "5m",
            numPredict: 2048,
            temperature: 0.2,
            notes: "",
            purpose: "Avoid keeping large models hot"
        )

        let applied = AppliedRuntimeProfile(profile: profile, currentModel: "gemma4:12b", modelMaxContext: 131_072)

        XCTAssertEqual(applied.model, "gemma4:12b")
        XCTAssertEqual(applied.numCtx, 4096)
        XCTAssertEqual(applied.keepAlive, "5m")
    }

    func testRuntimeProfileApplicationUsesPreferredModelWhenPresent() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Coding",
            preferredModel: "qwen3.6:27b-coding-mxfp8",
            contextPolicy: .balanced,
            contextOverrides: [],
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.1,
            notes: "",
            purpose: "Stable coding assistant"
        )

        let applied = AppliedRuntimeProfile(profile: profile, currentModel: "gemma4:12b", modelMaxContext: 16_384)

        XCTAssertEqual(applied.model, "qwen3.6:27b-coding-mxfp8")
        XCTAssertEqual(applied.numCtx, 16_384)
        XCTAssertEqual(applied.keepAlive, "30m")
    }

    func testRuntimeProfileApplicationUsesExactPerModelOverrideBeforePolicy() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Coding",
            preferredModel: "",
            contextPolicy: .lowRAM,
            contextOverrides: [
                ModelContextOverride(model: "gemma4:12b", numCtx: 32_768)
            ],
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.1,
            notes: "",
            purpose: "Stable coding assistant"
        )

        let applied = AppliedRuntimeProfile(profile: profile, currentModel: "gemma4:12b", modelMaxContext: 131_072)

        XCTAssertEqual(applied.numCtx, 32_768)
        XCTAssertEqual(applied.contextStatus, "num_ctx 32768 from per-model override.")
    }

    func testRuntimeProfileApplicationBuildsOllamaOptionsFromProfileParameters() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Sampling",
            preferredModel: "",
            contextPolicy: .balanced,
            contextOverrides: [],
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.2,
            generationOptions: ProfileGenerationOptions(
                temperature: 0.55,
                topP: 0.8,
                topK: 30,
                repeatPenalty: 1.15,
                repeatLastN: 128,
                seed: 123,
                mirostat: 2,
                mirostatTau: 5.0,
                mirostatEta: 0.1,
                numPredict: 1024
            ),
            notes: "",
            purpose: "Sampling test"
        )

        let applied = AppliedRuntimeProfile(profile: profile, currentModel: "gemma4:12b", modelMaxContext: 65_536)

        XCTAssertEqual(applied.options["num_ctx"], .number(32_768))
        XCTAssertEqual(applied.options["temperature"], .number(0.55))
        XCTAssertEqual(applied.options["top_p"], .number(0.8))
        XCTAssertEqual(applied.options["top_k"], .number(30))
        XCTAssertEqual(applied.options["repeat_penalty"], .number(1.15))
        XCTAssertEqual(applied.options["repeat_last_n"], .number(128))
        XCTAssertEqual(applied.options["seed"], .number(123))
        XCTAssertEqual(applied.options["mirostat"], .number(2))
        XCTAssertEqual(applied.options["mirostat_tau"], .number(5.0))
        XCTAssertEqual(applied.options["mirostat_eta"], .number(0.1))
        XCTAssertEqual(applied.options["num_predict"], .number(1024))
    }

    func testRuntimeProfileApplicationClampsOverrideToModelMaximum() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Long",
            preferredModel: "",
            contextPolicy: .maxKnown,
            contextOverrides: [
                ModelContextOverride(model: "llama3.2:latest", numCtx: 65_536)
            ],
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.2,
            notes: "",
            purpose: "Long context"
        )

        let applied = AppliedRuntimeProfile(profile: profile, currentModel: "llama3.2:latest", modelMaxContext: 8192)

        XCTAssertEqual(applied.numCtx, 8192)
        XCTAssertEqual(applied.contextStatus, "num_ctx 8192 from per-model override, clamped to model maximum.")
    }

    func testRuntimeProfileContextPoliciesResolveKnownAndUnknownMetadata() {
        XCTAssertNil(ProfileContextPolicy.modelDefault.resolve(modelMaxContext: 131_072))
        XCTAssertEqual(ProfileContextPolicy.lowRAM.resolve(modelMaxContext: nil), 4096)
        XCTAssertEqual(ProfileContextPolicy.lowRAM.resolve(modelMaxContext: 2048), 2048)
        XCTAssertNil(ProfileContextPolicy.balanced.resolve(modelMaxContext: nil))
        XCTAssertEqual(ProfileContextPolicy.balanced.resolve(modelMaxContext: 65_536), 32_768)
        XCTAssertNil(ProfileContextPolicy.maxKnown.resolve(modelMaxContext: nil))
        XCTAssertEqual(ProfileContextPolicy.maxKnown.resolve(modelMaxContext: 131_072), 131_072)
    }

    func testProfileEditorValueRulesClampNumericRuntimeFields() {
        XCTAssertEqual(ProfileEditorValueRules.clampedOverrideContextLength(-1), 1024)
        XCTAssertEqual(ProfileEditorValueRules.clampedOverrideContextLength(200_000), 131_072)
        XCTAssertEqual(ProfileEditorValueRules.clampedPredictionLimit(-1), 128)
        XCTAssertEqual(ProfileEditorValueRules.clampedPredictionLimit(100_000), 16_384)
        XCTAssertEqual(ProfileEditorValueRules.clampedTemperature(-0.5), 0, accuracy: 0.001)
        XCTAssertEqual(ProfileEditorValueRules.clampedTemperature(3.5), 2, accuracy: 0.001)
    }

    func testPreferredModelOptionsIncludeNoneInstalledModelsAndCurrentCustomModel() {
        let options = PreferredModelOptions.values(
            installedModelNames: ["llama3.2:latest", "gemma4:12b", "llama3.2:latest"],
            currentPreferredModel: "qwen3:8b"
        )

        XCTAssertEqual(options, ["", "llama3.2:latest", "gemma4:12b", "qwen3:8b"])
    }

    func testPreferredModelOptionsDoNotDuplicateCurrentInstalledModel() {
        let options = PreferredModelOptions.values(
            installedModelNames: ["llama3.2:latest", "gemma4:12b"],
            currentPreferredModel: "gemma4:12b"
        )

        XCTAssertEqual(options, ["", "llama3.2:latest", "gemma4:12b"])
    }

    func testKeepAliveOptionsIncludeStandardValuesAndCurrentCustomValue() {
        XCTAssertEqual(
            KeepAliveOptions.values(currentKeepAlive: "90m"),
            ["0", "5m", "30m", "1h", "4h", "24h", "-1", "90m"]
        )
        XCTAssertEqual(KeepAliveOptions.values(currentKeepAlive: "30m"), KeepAliveOptions.standardValues)
        XCTAssertEqual(KeepAliveOptions.label(for: "-1"), "-1 - keep loaded")
    }
}
