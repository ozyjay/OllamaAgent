import SwiftUI

struct ServiceStatusView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var proxy: OllamaProxyServer
    @ObservedObject var monitor: OllamaServiceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Logs")
                .font(.title3.bold())
            if let error = monitor.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Open Ollama Docs") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ollama/ollama/blob/main/docs/api.md")!)
                }
                Button("Open Local URL") {
                    NSWorkspace.shared.open(settings.baseURL)
                }
            }
            Divider()
            ProxyStatusView()
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnostics")
                    .font(.title3.bold())
                LogsView()
                    .frame(minHeight: 170)
                if settings.showAdvancedServiceNotes {
                    ServiceConfigurationView()
                } else {
                    Text("Enable advanced service configuration notes in Settings to show launchctl environment examples.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

private struct ProxyStatusView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var proxy: OllamaProxyServer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proxy")
                .font(.title3.bold())
            HStack(spacing: 8) {
                Label(proxy.isRunning ? "Running" : "Stopped", systemImage: proxy.isRunning ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(proxy.isRunning ? .green : .secondary)
                Text(proxy.statusMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Copy Proxy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(proxy.proxyURLString, forType: .string)
                }
                .disabled(!settings.enableProxy)
            }
            if settings.enableProxy {
                Text("Configure clients to use \(proxy.proxyURLString) instead of \(settings.baseURLString) to show authoritative Busy/Streaming activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("Enable the local proxy in Settings to track external client requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !proxy.activeRequests.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(proxy.activeRequests) { request in
                        HStack {
                            Text(request.model)
                                .font(.caption.weight(.semibold))
                            Text(request.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(DurationFormatter.date(request.startedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
