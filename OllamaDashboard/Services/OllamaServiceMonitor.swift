import Foundation

@MainActor
final class OllamaServiceMonitor: ObservableObject {
    @Published var version: OllamaVersion?
    @Published var installedModels: [InstalledModel] = []
    @Published var runningModels: [RunningModel] = []
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?
    @Published var isRefreshing = false

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isReachable: Bool {
        version != nil && errorMessage == nil
    }

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let client = OllamaAPIClient(baseURL: settings.baseURL)
        do {
            self.version = try await client.getVersion()
            installedModels = try await client.getInstalledModels()
            runningModels = try await client.getRunningModels()
            lastRefresh = Date()
            errorMessage = nil
        } catch {
            version = nil
            installedModels = []
            runningModels = []
            errorMessage = friendlyMessage(for: error)
        }
    }

    func warm(model: String, keepAlive: String, numCtx: Int?) async -> String {
        do {
            let client = OllamaAPIClient(baseURL: settings.baseURL)
            _ = try await client.warmModel(name: model, keepAlive: keepAlive, numCtx: numCtx)
            await refreshAll()
            return "Warmed \(model) with keep_alive \(keepAlive)."
        } catch {
            return friendlyMessage(for: error)
        }
    }

    func unload(model: String) async -> String {
        let client = OllamaAPIClient(baseURL: settings.baseURL)
        do {
            _ = try await client.unloadModelViaAPI(name: model)
            await refreshAll()
            return "Unloaded \(model) via API."
        } catch {
            guard settings.enableCLIControls else {
                return "API unload failed. Enable CLI-backed controls to try ollama stop."
            }
            do {
                let cli = OllamaCLIClient(executablePath: settings.ollamaCLIPath)
                try await cli.stopModel(name: model)
                await refreshAll()
                return "Stopped \(model) with ollama CLI."
            } catch {
                return friendlyMessage(for: error)
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "Ollama is unreachable. Confirm it is running at \(settings.baseURLString)."
    }
}
