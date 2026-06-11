import XCTest
@testable import OllamaAgent

@MainActor
final class ProfileAndSettingsTests: XCTestCase {
    func testSettingsPersistAllKeys() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: suite)
        settings.baseURLString = "http://example.test:11434"
        settings.refreshInterval = .tenSeconds
        settings.enableCLIControls = true
        settings.ollamaCLIPath = "/opt/homebrew/bin/ollama"
        settings.showAdvancedServiceNotes = true
        settings.enableProxy = true
        settings.proxyPort = 12_345
        settings.confirmUnload = false
        settings.enablePromptGuardrails = false
        settings.promptGuardrailResponseMode = .httpError
        settings.promptGuardrailWarnPromptCharacters = 10
        settings.promptGuardrailBlockPromptCharacters = 20
        settings.promptGuardrailWarnBodyBytes = 30
        settings.promptGuardrailBlockBodyBytes = 40
        settings.promptGuardrailWarnMessages = 5
        settings.promptGuardrailBlockMessages = 6
        settings.promptGuardrailWarnContextRatio = 0.5
        settings.promptGuardrailBlockContextRatio = 0.9

        let reloaded = AppSettings(defaults: suite)

        XCTAssertEqual(reloaded.baseURLString, "http://example.test:11434")
        XCTAssertEqual(reloaded.refreshInterval, .tenSeconds)
        XCTAssertTrue(reloaded.enableCLIControls)
        XCTAssertEqual(reloaded.ollamaCLIPath, "/opt/homebrew/bin/ollama")
        XCTAssertTrue(reloaded.showAdvancedServiceNotes)
        XCTAssertTrue(reloaded.enableProxy)
        XCTAssertEqual(reloaded.proxyPort, 12_345)
        XCTAssertFalse(reloaded.confirmUnload)
        XCTAssertFalse(reloaded.enablePromptGuardrails)
        XCTAssertEqual(reloaded.promptGuardrailResponseMode, .httpError)
        XCTAssertEqual(reloaded.promptGuardrailWarnPromptCharacters, 10)
        XCTAssertEqual(reloaded.promptGuardrailBlockPromptCharacters, 20)
        XCTAssertEqual(reloaded.promptGuardrailWarnBodyBytes, 30)
        XCTAssertEqual(reloaded.promptGuardrailBlockBodyBytes, 40)
        XCTAssertEqual(reloaded.promptGuardrailWarnMessages, 5)
        XCTAssertEqual(reloaded.promptGuardrailBlockMessages, 6)
        XCTAssertEqual(reloaded.promptGuardrailWarnContextRatio, 0.5)
        XCTAssertEqual(reloaded.promptGuardrailBlockContextRatio, 0.9)
    }

    func testSettingsMigrateLegacyDefaultsWithoutOverwritingNewValues() {
        let newSuiteName = UUID().uuidString
        let legacySuiteName = UUID().uuidString
        let newDefaults = UserDefaults(suiteName: newSuiteName)!
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        newDefaults.removePersistentDomain(forName: newSuiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        legacyDefaults.set("http://legacy.test:11434", forKey: "baseURLString")
        legacyDefaults.set("tenSeconds", forKey: "refreshInterval")
        legacyDefaults.set(true, forKey: "enableProxy")
        legacyDefaults.set(12_345, forKey: "proxyPort")
        newDefaults.set(11_111, forKey: "proxyPort")

        let settings = AppSettings(defaults: newDefaults, legacyDefaults: legacyDefaults)

        XCTAssertEqual(settings.baseURLString, "http://legacy.test:11434")
        XCTAssertEqual(settings.refreshInterval, .tenSeconds)
        XCTAssertTrue(settings.enableProxy)
        XCTAssertEqual(settings.proxyPort, 11_111)
    }

    func testProfileManagerFallsBackToBuiltInsForMissingEmptyAndCorruptFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingFile = directory.appendingPathComponent("missing.json")

        let missing = ProfileManager(fileURL: missingFile)
        XCTAssertEqual(missing.profiles.map(\.name), RuntimeProfile.builtIns.map(\.name))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let emptyFile = directory.appendingPathComponent("empty.json")
        try Data("[]".utf8).write(to: emptyFile)
        let empty = ProfileManager(fileURL: emptyFile)
        XCTAssertEqual(empty.profiles.map(\.name), RuntimeProfile.builtIns.map(\.name))

        let corruptFile = directory.appendingPathComponent("corrupt.json")
        try Data("{ not json".utf8).write(to: corruptFile)
        let corrupt = ProfileManager(fileURL: corruptFile)
        XCTAssertEqual(corrupt.profiles.map(\.name), RuntimeProfile.builtIns.map(\.name))
    }

    func testProfileManagerResetPersistsBuiltIns() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("profiles.json")
        let manager = ProfileManager(fileURL: fileURL)
        manager.profiles = [
            RuntimeProfile(
                id: UUID(),
                name: "Temporary",
                preferredModel: "",
                contextPolicy: .modelDefault,
                contextOverrides: [],
                keepAlive: "5m",
                numPredict: 128,
                temperature: 0.1,
                notes: "",
                purpose: "Test"
            )
        ]
        try manager.save()

        try manager.resetToBuiltIns()
        let reloaded = ProfileManager(fileURL: fileURL)

        XCTAssertEqual(reloaded.profiles.map(\.name), RuntimeProfile.builtIns.map(\.name))
    }

    func testRuntimeProfileModelDefaultStatusAndFallbackOptions() {
        let profile = RuntimeProfile(
            id: UUID(),
            name: "Default",
            preferredModel: "",
            contextPolicy: .modelDefault,
            contextOverrides: [],
            keepAlive: "5m",
            numPredict: 512,
            temperature: 0.3,
            generationOptions: ProfileGenerationOptions(),
            notes: "",
            purpose: "Defaults"
        )

        let applied = AppliedRuntimeProfile(profile: profile, currentModel: "llama3.2:latest", modelMaxContext: 131_072)

        XCTAssertNil(applied.numCtx)
        XCTAssertEqual(applied.contextStatus, "Using Ollama model default context.")
        XCTAssertEqual(applied.options["temperature"], .number(0.3))
        XCTAssertEqual(applied.options["num_predict"], .number(512))
        XCTAssertNil(applied.options["num_ctx"])
    }
}
