import AppKit
import SwiftUI

struct StatusMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var navigation: DashboardNavigation
    @EnvironmentObject private var proxy: OllamaProxyServer
    @ObservedObject var monitor: OllamaServiceMonitor
    let refreshAction: () -> Void

    var body: some View {
        Label(
            monitor.isReachable ? "Ollama reachable" : "Ollama offline",
            systemImage: monitor.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .disabled(true)

        Text(proxy.statusMessage)
            .lineLimit(2)
            .disabled(true)

        Divider()

        Button("Open Dashboard") {
            openDashboard()
        }

        ForEach(StatusMenuDestination.allCases) { destination in
            Button(destination.title) {
                openDashboard(selecting: destination.tab)
            }
        }

        Divider()

        Button("Refresh Now") {
            refreshAction()
        }

        Divider()

        Button("Quit OllamaDashboard") {
            NSApp.terminate(nil)
        }
    }

    private func openDashboard(selecting tab: DashboardTab? = nil) {
        if let tab {
            navigation.selectedTab = tab
        }
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}
