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
                .appendingPathComponent("OllamaDashboard", isDirectory: true)
            self.fileURL = support.appendingPathComponent("profiles.json")
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

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
