import Combine
import Foundation

@MainActor
final class AgentRuntime: ObservableObject {
    let settings: AppSettings
    let profiles: ProfileManager
    let proxy: OllamaProxyServer
    let controlServer: AgentControlServer
    let monitor: OllamaServiceMonitor
    let navigation = AgentNavigation()

    private var autoRefreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings = AppSettings(),
        profiles: ProfileManager = ProfileManager(),
        proxy: OllamaProxyServer = OllamaProxyServer(),
        controlServer: AgentControlServer = AgentControlServer()
    ) {
        self.settings = settings
        self.profiles = profiles
        self.proxy = proxy
        self.controlServer = controlServer
        monitor = OllamaServiceMonitor(settings: settings)
        configureBindings()
        configureAutoRefresh()
        refreshNow()
        applyProxySettings()
        controlServer.start(runtime: self)
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    func refreshNow() {
        Task { await monitor.refreshAll() }
    }

    private func configureBindings() {
        settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.configureAutoRefresh() }
            }
            .store(in: &cancellables)

        settings.$enableProxy
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$proxyPort
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$baseURLString
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$enablePromptGuardrails
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailResponseMode
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailWarnPromptCharacters
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailBlockPromptCharacters
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailWarnBodyBytes
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailBlockBodyBytes
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailWarnMessages
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailBlockMessages
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailWarnContextRatio
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)

        settings.$promptGuardrailBlockContextRatio
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyProxySettings() }
            }
            .store(in: &cancellables)
    }

    private func configureAutoRefresh() {
        autoRefreshTask?.cancel()
        guard let seconds = settings.refreshInterval.seconds else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await self?.monitor.refreshAll()
            }
        }
    }

    private func applyProxySettings() {
        Task { await proxy.apply(settings: settings) }
    }
}
