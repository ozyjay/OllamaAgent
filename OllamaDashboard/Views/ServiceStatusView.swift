import SwiftUI

struct ServiceStatusView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var monitor: OllamaServiceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Service Status")
                .font(.title3.bold())
            InfoRow(label: "Reachability", value: monitor.isReachable ? "Ollama is reachable" : "Ollama is unreachable")
            InfoRow(label: "Version", value: monitor.version?.version ?? "Unknown")
            InfoRow(label: "Base URL", value: settings.baseURLString)
            InfoRow(label: "Last refresh", value: DurationFormatter.date(monitor.lastRefresh))
            if let error = monitor.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Refresh") {
                    Task { await monitor.refreshAll() }
                }
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
