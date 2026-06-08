import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var detectionStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.title3.bold())
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Ollama base URL")
                    TextField("Ollama base URL", text: $settings.baseURLString)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Refresh interval")
                    Picker("Refresh interval", selection: $settings.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150, alignment: .leading)
                }
                GridRow {
                    Spacer()
                    Toggle("Enable CLI-backed controls", isOn: $settings.enableCLIControls)
                }
                GridRow {
                    Text("ollama CLI path")
                    HStack(spacing: 8) {
                        TextField("ollama CLI path", text: $settings.ollamaCLIPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Auto-detect") {
                            Task { await detectCLI() }
                        }
                    }
                }
            }
            Toggle("Show advanced service configuration notes", isOn: $settings.showAdvancedServiceNotes)
            Toggle("Read local Ollama logs", isOn: $settings.readLocalLogs)
            Toggle("Confirm before unloading models", isOn: $settings.confirmUnload)
            if !detectionStatus.isEmpty {
                Text(detectionStatus).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detectCLI() async {
        if let path = await OllamaCLIClient(executablePath: settings.ollamaCLIPath).findOllamaBinary() {
            settings.ollamaCLIPath = path
            detectionStatus = "Found \(path)"
        } else {
            detectionStatus = "ollama CLI not found."
        }
    }
}
