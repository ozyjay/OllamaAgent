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
    @State private var rawLogText = ""
    @State private var selectedCategories: Set<OllamaLogCategory> = []
    @State private var logSearchText = ""
    @State private var isUpdatingLogs = false
    @State private var logUpdateTask: Task<Void, Never>?

    private var displayedLogText: String {
        OllamaLogClassifier.filteredLines(
            in: rawLogText,
            selectedCategories: selectedCategories,
            searchText: logSearchText
        )
    }

    private var displayedLogEntries: [OllamaLogEntry] {
        OllamaLogClassifier.entries(
            in: rawLogText,
            selectedCategories: selectedCategories,
            searchText: logSearchText
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logs").font(.title3.bold())
            HStack {
                Button(isUpdatingLogs ? "Stop Log Updates" : "Start Log Updates") {
                    toggleLogUpdates()
                }
                Button("Copy Logs") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(displayedLogText, forType: .string)
                }
                Button("Clear View") { rawLogText = "" }
            }
            LogFilterBar(
                selectedCategories: $selectedCategories,
                searchText: $logSearchText
            )
            Text("Showing the last \(OllamaLogTail.defaultMaxLines) lines from at most \(ByteFormatter.string(from: Int64(OllamaLogTail.defaultMaxBytes))) of the local Ollama server log.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                if displayedLogEntries.isEmpty {
                    Text(emptyLogMessage)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(displayedLogEntries) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onDisappear {
            stopLogUpdates()
        }
    }

    private var emptyLogMessage: String {
        rawLogText.isEmpty ? "Start log updates to load recent log lines." : "No log lines match the current filters."
    }

    private func toggleLogUpdates() {
        if isUpdatingLogs {
            stopLogUpdates()
        } else {
            startLogUpdates()
        }
    }

    private func startLogUpdates() {
        guard !isUpdatingLogs else { return }
        isUpdatingLogs = true
        logUpdateTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopLogUpdates() {
        isUpdatingLogs = false
        logUpdateTask?.cancel()
        logUpdateTask = nil
    }

    private func refresh() async {
        do {
            let chronologicalLogs = try await OllamaCLIClient(executablePath: settings.ollamaCLIPath).readLogs(
                maxLines: OllamaLogTail.defaultMaxLines,
                maxBytes: OllamaLogTail.defaultMaxBytes
            )
            rawLogText = OllamaLogTail.newestFirst(chronologicalLogs)
        } catch {
            rawLogText = error.localizedDescription
        }
    }
}

private struct LogEntryRow: View {
    let entry: OllamaLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.severity.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(labelColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(labelColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summaryColor)
                    .lineLimit(2)
                Text(entry.detail)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
    }

    private var labelColor: Color {
        switch entry.severity {
        case .error: return .red
        case .warning: return .orange
        case .request: return .blue
        case .model: return .purple
        case .lifecycle: return .green
        case .info: return .secondary
        }
    }

    private var summaryColor: Color {
        entry.severity == .error ? .red : .primary
    }

    private var rowBackground: Color {
        switch entry.severity {
        case .error: return .red.opacity(0.08)
        case .warning: return .orange.opacity(0.08)
        case .request: return .blue.opacity(0.07)
        case .model: return .purple.opacity(0.07)
        case .lifecycle: return .green.opacity(0.07)
        case .info: return .secondary.opacity(0.06)
        }
    }
}

private struct LogFilterBar: View {
    @Binding var selectedCategories: Set<OllamaLogCategory>
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(OllamaLogCategory.allCases) { category in
                    Toggle(category.rawValue, isOn: binding(for: category))
                        .toggleStyle(.button)
                        .controlSize(.small)
                }
                Button("All") {
                    selectedCategories = []
                    searchText = ""
                }
                .controlSize(.small)
            }
            TextField("Filter log text", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func binding(for category: OllamaLogCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isSelected in
                if isSelected {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
            }
        )
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
