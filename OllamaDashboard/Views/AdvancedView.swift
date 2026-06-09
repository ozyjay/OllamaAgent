import SwiftUI

struct AdvancedView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            LogsView()
                .tabItem { Text("Logs") }
            ServiceConfigurationView()
                .tabItem { Text("Service Config") }
        }
        .frame(minHeight: 420)
    }
}

struct LogsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var logText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logs").font(.title3.bold())
            HStack {
                Button("Refresh") { Task { await refresh() } }
                    .disabled(!settings.readLocalLogs)
                Button("Copy Logs") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                Button("Clear View") { logText = "" }
            }
            ScrollView {
                Text(settings.readLocalLogs ? (logText.isEmpty ? "No log lines loaded." : logText) : "Enable local log reading in Settings.")
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func refresh() async {
        do {
            logText = try await OllamaCLIClient(executablePath: settings.ollamaCLIPath).readLogs(maxLines: 200)
        } catch {
            logText = error.localizedDescription
        }
    }
}

struct ServiceConfigurationView: View {
    private let variables = ServiceVariable.defaults

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Service Configuration").font(.title3.bold())
            Text("These notes are non-destructive. Updating launchctl environment values may require restarting Ollama.")
                .foregroundStyle(.secondary)
            Table(variables) {
                TableColumn("Variable") { variable in
                    Text(variable.name).textSelection(.enabled)
                }
                TableColumn("Observed") { variable in
                    Text(ProcessInfo.processInfo.environment[variable.name] ?? "unknown")
                }
                TableColumn("Command") { variable in
                    let command = "launchctl setenv \(variable.name) <value>"
                    HStack {
                        Text(command).font(.system(.caption, design: .monospaced)).lineLimit(1)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 260)
        }
    }
}

private struct ServiceVariable: Identifiable {
    var id: String { name }
    let name: String

    static let defaults = [
        ServiceVariable(name: "OLLAMA_HOST"),
        ServiceVariable(name: "OLLAMA_CONTEXT_LENGTH"),
        ServiceVariable(name: "OLLAMA_MAX_LOADED_MODELS"),
        ServiceVariable(name: "OLLAMA_NUM_PARALLEL"),
        ServiceVariable(name: "OLLAMA_KEEP_ALIVE"),
        ServiceVariable(name: "OLLAMA_MODELS"),
        ServiceVariable(name: "OLLAMA_NO_CLOUD")
    ]
}
