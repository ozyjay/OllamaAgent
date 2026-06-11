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
    @Published var enableProxy: Bool {
        didSet { defaults.set(enableProxy, forKey: Keys.enableProxy) }
    }
    @Published var proxyPort: Int {
        didSet { defaults.set(proxyPort, forKey: Keys.proxyPort) }
    }
    @Published var confirmUnload: Bool {
        didSet { defaults.set(confirmUnload, forKey: Keys.confirmUnload) }
    }
    @Published var enablePromptGuardrails: Bool {
        didSet { defaults.set(enablePromptGuardrails, forKey: Keys.enablePromptGuardrails) }
    }
    @Published var promptGuardrailResponseMode: PromptGuardrailResponseMode {
        didSet { defaults.set(promptGuardrailResponseMode.rawValue, forKey: Keys.promptGuardrailResponseMode) }
    }
    @Published var promptGuardrailWarnPromptCharacters: Int {
        didSet { defaults.set(promptGuardrailWarnPromptCharacters, forKey: Keys.promptGuardrailWarnPromptCharacters) }
    }
    @Published var promptGuardrailBlockPromptCharacters: Int {
        didSet { defaults.set(promptGuardrailBlockPromptCharacters, forKey: Keys.promptGuardrailBlockPromptCharacters) }
    }
    @Published var promptGuardrailWarnBodyBytes: Int {
        didSet { defaults.set(promptGuardrailWarnBodyBytes, forKey: Keys.promptGuardrailWarnBodyBytes) }
    }
    @Published var promptGuardrailBlockBodyBytes: Int {
        didSet { defaults.set(promptGuardrailBlockBodyBytes, forKey: Keys.promptGuardrailBlockBodyBytes) }
    }
    @Published var promptGuardrailWarnMessages: Int {
        didSet { defaults.set(promptGuardrailWarnMessages, forKey: Keys.promptGuardrailWarnMessages) }
    }
    @Published var promptGuardrailBlockMessages: Int {
        didSet { defaults.set(promptGuardrailBlockMessages, forKey: Keys.promptGuardrailBlockMessages) }
    }
    @Published var promptGuardrailWarnContextRatio: Double {
        didSet { defaults.set(promptGuardrailWarnContextRatio, forKey: Keys.promptGuardrailWarnContextRatio) }
    }
    @Published var promptGuardrailBlockContextRatio: Double {
        didSet { defaults.set(promptGuardrailBlockContextRatio, forKey: Keys.promptGuardrailBlockContextRatio) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseURLString = defaults.string(forKey: Keys.baseURLString) ?? "http://localhost:11434"
        refreshInterval = RefreshInterval(rawValue: defaults.string(forKey: Keys.refreshInterval) ?? "") ?? .manual
        enableCLIControls = defaults.object(forKey: Keys.enableCLIControls) as? Bool ?? false
        ollamaCLIPath = defaults.string(forKey: Keys.ollamaCLIPath) ?? "/usr/local/bin/ollama"
        showAdvancedServiceNotes = defaults.object(forKey: Keys.showAdvancedServiceNotes) as? Bool ?? false
        enableProxy = defaults.object(forKey: Keys.enableProxy) as? Bool ?? false
        proxyPort = defaults.object(forKey: Keys.proxyPort) as? Int ?? 11_435
        confirmUnload = defaults.object(forKey: Keys.confirmUnload) as? Bool ?? true
        enablePromptGuardrails = defaults.object(forKey: Keys.enablePromptGuardrails) as? Bool ?? true
        promptGuardrailResponseMode = PromptGuardrailResponseMode(
            rawValue: defaults.string(forKey: Keys.promptGuardrailResponseMode) ?? ""
        ) ?? .assistantMessage
        promptGuardrailWarnPromptCharacters = defaults.object(forKey: Keys.promptGuardrailWarnPromptCharacters) as? Int ?? 120_000
        promptGuardrailBlockPromptCharacters = defaults.object(forKey: Keys.promptGuardrailBlockPromptCharacters) as? Int ?? 300_000
        promptGuardrailWarnBodyBytes = defaults.object(forKey: Keys.promptGuardrailWarnBodyBytes) as? Int ?? 1_000_000
        promptGuardrailBlockBodyBytes = defaults.object(forKey: Keys.promptGuardrailBlockBodyBytes) as? Int ?? 2_500_000
        promptGuardrailWarnMessages = defaults.object(forKey: Keys.promptGuardrailWarnMessages) as? Int ?? 20
        promptGuardrailBlockMessages = defaults.object(forKey: Keys.promptGuardrailBlockMessages) as? Int ?? 60
        promptGuardrailWarnContextRatio = defaults.object(forKey: Keys.promptGuardrailWarnContextRatio) as? Double ?? 0.75
        promptGuardrailBlockContextRatio = defaults.object(forKey: Keys.promptGuardrailBlockContextRatio) as? Double ?? 1.10
    }

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: "http://localhost:11434")!
    }

    var promptGuardrailPolicy: PromptGuardrailPolicy {
        guard enablePromptGuardrails else { return .disabled(responseMode: promptGuardrailResponseMode) }
        return PromptGuardrailPolicy(
            enabled: true,
            responseMode: promptGuardrailResponseMode,
            warnPromptCharacters: promptGuardrailWarnPromptCharacters,
            blockPromptCharacters: promptGuardrailBlockPromptCharacters,
            warnBodyBytes: promptGuardrailWarnBodyBytes,
            blockBodyBytes: promptGuardrailBlockBodyBytes,
            warnMessages: promptGuardrailWarnMessages,
            blockMessages: promptGuardrailBlockMessages,
            warnContextRatio: promptGuardrailWarnContextRatio,
            blockContextRatio: promptGuardrailBlockContextRatio
        )
    }
}

enum PromptGuardrailResponseMode: String, CaseIterable, Identifiable {
    case assistantMessage
    case httpError

    var id: String { rawValue }

    var label: String {
        switch self {
        case .assistantMessage: return "Assistant message"
        case .httpError: return "HTTP error"
        }
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
    static let enableProxy = "enableProxy"
    static let proxyPort = "proxyPort"
    static let confirmUnload = "confirmUnload"
    static let enablePromptGuardrails = "enablePromptGuardrails"
    static let promptGuardrailResponseMode = "promptGuardrailResponseMode"
    static let promptGuardrailWarnPromptCharacters = "promptGuardrailWarnPromptCharacters"
    static let promptGuardrailBlockPromptCharacters = "promptGuardrailBlockPromptCharacters"
    static let promptGuardrailWarnBodyBytes = "promptGuardrailWarnBodyBytes"
    static let promptGuardrailBlockBodyBytes = "promptGuardrailBlockBodyBytes"
    static let promptGuardrailWarnMessages = "promptGuardrailWarnMessages"
    static let promptGuardrailBlockMessages = "promptGuardrailBlockMessages"
    static let promptGuardrailWarnContextRatio = "promptGuardrailWarnContextRatio"
    static let promptGuardrailBlockContextRatio = "promptGuardrailBlockContextRatio"
}
