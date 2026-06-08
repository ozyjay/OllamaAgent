import SwiftUI

@main
struct OllamaDashboardApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var profiles = ProfileManager()
    @StateObject private var monitor: OllamaServiceMonitor

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: OllamaServiceMonitor(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra("OllamaDashboard", systemImage: "helm") {
            MenuBarView(monitor: monitor)
                .environmentObject(settings)
                .environmentObject(profiles)
                .frame(width: 720, height: 560)
        }
        .menuBarExtraStyle(.window)
    }
}
