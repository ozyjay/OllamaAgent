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

        manager.profiles[0].preferredModel = "llama3.2:latest"
        try manager.save()

        let reloaded = ProfileManager(fileURL: fileURL)
        XCTAssertEqual(reloaded.profiles[0].preferredModel, "llama3.2:latest")
    }

    func testSettingsDefaults() {
        let suiteName = UUID().uuidString
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: suite)

        XCTAssertEqual(settings.baseURLString, "http://localhost:11434")
        XCTAssertEqual(settings.refreshInterval, .manual)
        XCTAssertFalse(settings.enableCLIControls)
        XCTAssertTrue(settings.confirmUnload)
    }
}
