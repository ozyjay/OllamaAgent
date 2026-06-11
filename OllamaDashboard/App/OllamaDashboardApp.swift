import SwiftUI

@main
struct OllamaDashboardApp: App {
    @StateObject private var runtime = DashboardRuntime()

    var body: some Scene {
        Window("OllamaDashboard", id: "dashboard") {
            DashboardWindowView(monitor: runtime.monitor, refreshAction: runtime.refreshNow)
                .dashboardEnvironment(runtime)
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(runtime.settings)
        }

        MenuBarExtra {
            StatusMenuView(monitor: runtime.monitor, refreshAction: runtime.refreshNow)
                .environmentObject(runtime.navigation)
                .environmentObject(runtime.proxy)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
    }
}

private extension View {
    func dashboardEnvironment(_ runtime: DashboardRuntime) -> some View {
        environmentObject(runtime.settings)
            .environmentObject(runtime.profiles)
            .environmentObject(runtime.proxy)
            .environmentObject(runtime.navigation)
    }
}
