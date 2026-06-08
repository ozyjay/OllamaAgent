import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: Keys.baseURLString) }
    }
    @Published var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval) }
    }
    @Published var enableCLIControls: Bool {
        didSet { defaults.set(enableCLIControls, forKey: Keys.enableCLIControls) }
    }
    @Published var ollamaCLIPath: String {
        didSet { defaults.set(ollamaCLIPath, forKey: Keys.ollamaCLIPath) }
    }
    @Published var showAdvancedServiceNotes: Bool {
        didSet { defaults.set(showAdvancedServiceNotes, forKey: Keys.showAdvancedServiceNotes) }
    }
    @Published var readLocalLogs: Bool {
        didSet { defaults.set(readLocalLogs, forKey: Keys.readLocalLogs) }
    }
    @Published var confirmUnload: Bool {
        didSet { defaults.set(confirmUnload, forKey: Keys.confirmUnload) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURLString = defaults.string(forKey: Keys.baseURLString) ?? "http://localhost:11434"
        refreshInterval = RefreshInterval(rawValue: defaults.string(forKey: Keys.refreshInterval) ?? "") ?? .manual
        enableCLIControls = defaults.object(forKey: Keys.enableCLIControls) as? Bool ?? false
        ollamaCLIPath = defaults.string(forKey: Keys.ollamaCLIPath) ?? "/usr/local/bin/ollama"
        showAdvancedServiceNotes = defaults.object(forKey: Keys.showAdvancedServiceNotes) as? Bool ?? false
        readLocalLogs = defaults.object(forKey: Keys.readLocalLogs) as? Bool ?? false
        confirmUnload = defaults.object(forKey: Keys.confirmUnload) as? Bool ?? true
    }

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: "http://localhost:11434")!
    }
}

enum RefreshInterval: String, CaseIterable, Identifiable {
    case manual
    case fiveSeconds
    case tenSeconds
    case thirtySeconds

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .fiveSeconds: return "5s"
        case .tenSeconds: return "10s"
        case .thirtySeconds: return "30s"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .manual: return nil
        case .fiveSeconds: return 5
        case .tenSeconds: return 10
        case .thirtySeconds: return 30
        }
    }
}

private enum Keys {
    static let baseURLString = "baseURLString"
    static let refreshInterval = "refreshInterval"
    static let enableCLIControls = "enableCLIControls"
    static let ollamaCLIPath = "ollamaCLIPath"
    static let showAdvancedServiceNotes = "showAdvancedServiceNotes"
    static let readLocalLogs = "readLocalLogs"
    static let confirmUnload = "confirmUnload"
}
