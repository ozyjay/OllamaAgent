import SwiftUI

@main
struct OllamaAgentApp: App {
    @StateObject private var runtime = AgentRuntime()

    var body: some Scene {
        Window("OllamaAgent", id: "agent") {
            AgentWindowView(monitor: runtime.monitor, refreshAction: runtime.refreshNow)
                .agentEnvironment(runtime)
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
    func agentEnvironment(_ runtime: AgentRuntime) -> some View {
        environmentObject(runtime.settings)
            .environmentObject(runtime.profiles)
            .environmentObject(runtime.proxy)
            .environmentObject(runtime.navigation)
    }
}
