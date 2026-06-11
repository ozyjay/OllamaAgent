import Foundation

@MainActor
final class ProfileManager: ObservableObject {
    @Published var profiles: [RuntimeProfile] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("OllamaAgent", isDirectory: true)
            self.fileURL = support.appendingPathComponent("profiles.json")
            migrateLegacyProfilesIfNeeded(to: self.fileURL)
        }
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            profiles = try JSONDecoder().decode([RuntimeProfile].self, from: data)
            if profiles.isEmpty {
                profiles = RuntimeProfile.builtIns
            }
        } catch {
            profiles = RuntimeProfile.builtIns
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(profiles)
        try data.write(to: fileURL, options: .atomic)
    }

    func resetToBuiltIns() throws {
        profiles = RuntimeProfile.builtIns
        try save()
    }
}

private extension ProfileManager {
    func migrateLegacyProfilesIfNeeded(to newFileURL: URL) {
        guard !FileManager.default.fileExists(atPath: newFileURL.path),
              let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        let legacyFileURL = applicationSupport
            .appendingPathComponent("OllamaDashboard", isDirectory: true)
            .appendingPathComponent("profiles.json")
        guard FileManager.default.fileExists(atPath: legacyFileURL.path) else { return }

        do {
            try FileManager.default.createDirectory(
                at: newFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: legacyFileURL, to: newFileURL)
        } catch {
            // Loading will fall back to built-ins if migration cannot complete.
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
