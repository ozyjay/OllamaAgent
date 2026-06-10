import SwiftUI

@main
struct OllamaDashboardApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var profiles = ProfileManager()
    @StateObject private var monitor: OllamaServiceMonitor
    @StateObject private var proxy: OllamaProxyServer

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: OllamaServiceMonitor(settings: settings))
        _proxy = StateObject(wrappedValue: OllamaProxyServer())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
                .environmentObject(settings)
                .environmentObject(profiles)
                .environmentObject(proxy)
                .frame(width: 720, height: 560)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .accessibilityLabel("OllamaDashboard")
        }
        .menuBarExtraStyle(.window)
    }
}
