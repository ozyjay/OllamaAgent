import XCTest
@testable import OllamaDashboard

@MainActor
final class OllamaServiceMonitorTests: XCTestCase {
    func testRefreshSuccessPopulatesStateAndClearsError() async {
        let settings = makeSettings()
        let monitor = OllamaServiceMonitor(
            settings: settings,
            apiClientFactory: { _ in
                StubAPIClient(
                    versionResult: .success(OllamaVersion(version: "0.9.1")),
                    installedResult: .success([makeInstalledModel(name: "llama3.2:latest")]),
                    runningResult: .success([makeRunningModel(name: "llama3.2:latest")])
                )
            }
        )

        await monitor.refreshAll()

        XCTAssertEqual(monitor.version?.version, "0.9.1")
        XCTAssertEqual(monitor.installedModels.map(\.name), ["llama3.2:latest"])
        XCTAssertEqual(monitor.runningModels.map(\.name), ["llama3.2:latest"])
        XCTAssertNotNil(monitor.lastRefresh)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertFalse(monitor.isRefreshing)
        XCTAssertTrue(monitor.isReachable)
    }

    func testRefreshFailureClearsStaleStateAndStoresFriendlyError() async {
        let monitor = OllamaServiceMonitor(
            settings: makeSettings(),
            apiClientFactory: { _ in
                StubAPIClient(versionResult: .failure(TestError(message: "offline")))
            }
        )
        monitor.version = OllamaVersion(version: "old")
        monitor.installedModels = [makeInstalledModel(name: "stale")]
        monitor.runningModels = [makeRunningModel(name: "stale")]

        await monitor.refreshAll()

        XCTAssertNil(monitor.version)
        XCTAssertTrue(monitor.installedModels.isEmpty)
        XCTAssertTrue(monitor.runningModels.isEmpty)
        XCTAssertEqual(monitor.errorMessage, "offline")
        XCTAssertFalse(monitor.isReachable)
    }

    func testWarmSuccessCallsAPIRefreshesAndReturnsMessage() async {
        var warmed: (String, String, Int?, [String: JSONValue])?
        var factoryCalls = 0
        let monitor = OllamaServiceMonitor(
            settings: makeSettings(),
            apiClientFactory: { _ in
                factoryCalls += 1
                return StubAPIClient(
                    versionResult: .success(OllamaVersion(version: "0.9.1")),
                    installedResult: .success([makeInstalledModel(name: "qwen2.5-coder:7b")]),
                    runningResult: .success([makeRunningModel(name: "qwen2.5-coder:7b")]),
                    warmResult: .success(WarmModelResult(model: "qwen2.5-coder:7b", keepAlive: "1h", loaded: true)),
                    onWarm: { model, keepAlive, numCtx, options in
                        warmed = (model, keepAlive, numCtx, options)
                    }
                )
            }
        )

        let message = await monitor.warm(
            model: "qwen2.5-coder:7b",
            keepAlive: "1h",
            numCtx: 8192,
            options: ["temperature": .number(0.2)]
        )

        XCTAssertEqual(message, "Warmed qwen2.5-coder:7b.")
        XCTAssertEqual(warmed?.0, "qwen2.5-coder:7b")
        XCTAssertEqual(warmed?.1, "1h")
        XCTAssertEqual(warmed?.2, 8192)
        XCTAssertEqual(warmed?.3["temperature"], .number(0.2))
        XCTAssertEqual(monitor.version?.version, "0.9.1")
        XCTAssertGreaterThanOrEqual(factoryCalls, 2)
    }

    func testWarmFailureReturnsFriendlyMessage() async {
        let monitor = OllamaServiceMonitor(
            settings: makeSettings(),
            apiClientFactory: { _ in
                StubAPIClient(warmResult: .failure(TestError(message: "warm failed")))
            }
        )

        let message = await monitor.warm(model: "llama3.2:latest", keepAlive: "30m", numCtx: nil)

        XCTAssertEqual(message, "warm failed")
    }

    func testUnloadAPISuccessRefreshesAndSkipsCLI() async {
        let cli = StubCLIClient()
        var apiUnloadCount = 0
        let monitor = OllamaServiceMonitor(
            settings: makeSettings(enableCLIControls: true),
            apiClientFactory: { _ in
                StubAPIClient(
                    versionResult: .success(OllamaVersion(version: "0.9.1")),
                    installedResult: .success([]),
                    runningResult: .success([]),
                    unloadResult: .success(UnloadResult(model: "llama3.2:latest", method: "API keep_alive=0", unloaded: true)),
                    onUnload: { _ in apiUnloadCount += 1 }
                )
            },
            cliClientFactory: { _ in cli }
        )

        let message = await monitor.unload(model: "llama3.2:latest")

        XCTAssertEqual(message, "Unloaded llama3.2:latest via API.")
        XCTAssertEqual(apiUnloadCount, 1)
        XCTAssertTrue(cli.stoppedModels.isEmpty)
    }

    func testUnloadAPIFailureWithCLIDisabledReturnsEnableMessage() async {
        let cli = StubCLIClient()
        let monitor = OllamaServiceMonitor(
            settings: makeSettings(enableCLIControls: false),
            apiClientFactory: { _ in
                StubAPIClient(unloadResult: .failure(TestError(message: "api failed")))
            },
            cliClientFactory: { _ in cli }
        )

        let message = await monitor.unload(model: "llama3.2:latest")

        XCTAssertEqual(message, "API unload failed. Enable CLI-backed controls to try ollama stop.")
        XCTAssertTrue(cli.stoppedModels.isEmpty)
    }

    func testUnloadAPIFailureWithCLIEnabledFallsBackToCLIAndRefreshes() async {
        let cli = StubCLIClient()
        let monitor = OllamaServiceMonitor(
            settings: makeSettings(enableCLIControls: true),
            apiClientFactory: { _ in
                StubAPIClient(
                    versionResult: .success(OllamaVersion(version: "0.9.1")),
                    installedResult: .success([]),
                    runningResult: .success([]),
                    unloadResult: .failure(TestError(message: "api failed"))
                )
            },
            cliClientFactory: { _ in cli }
        )

        let message = await monitor.unload(model: "llama3.2:latest")

        XCTAssertEqual(message, "Stopped llama3.2:latest with ollama CLI.")
        XCTAssertEqual(cli.stoppedModels, ["llama3.2:latest"])
        XCTAssertEqual(monitor.version?.version, "0.9.1")
    }

    func testUnloadCLIFallbackFailureReportsCLIError() async {
        let cli = StubCLIClient()
        cli.stopResult = .failure(TestError(message: "cli failed"))
        let monitor = OllamaServiceMonitor(
            settings: makeSettings(enableCLIControls: true),
            apiClientFactory: { _ in
                StubAPIClient(unloadResult: .failure(TestError(message: "api failed")))
            },
            cliClientFactory: { _ in cli }
        )

        let message = await monitor.unload(model: "llama3.2:latest")

        XCTAssertEqual(message, "cli failed")
        XCTAssertEqual(cli.stoppedModels, ["llama3.2:latest"])
    }

    private func makeSettings(enableCLIControls: Bool = false) -> AppSettings {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: suite)
        settings.enableCLIControls = enableCLIControls
        return settings
    }
}
