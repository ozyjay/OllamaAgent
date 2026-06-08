import SwiftUI

struct ServiceStatusView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var monitor: OllamaServiceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service")
                .font(.title3.bold())
            if let error = monitor.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await monitor.refreshAll() }
                }
                .disabled(monitor.isRefreshing)
                Button("Open Ollama Docs") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ollama/ollama/blob/main/docs/api.md")!)
                }
                Button("Open Local URL") {
                    NSWorkspace.shared.open(settings.baseURL)
                }
            }
            Spacer()
        }
    }
}
