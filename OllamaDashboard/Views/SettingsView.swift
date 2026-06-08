import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var detectionStatus = ""

    var body: some View {
        Form {
            Text("Settings").font(.title3.bold())
            TextField("Ollama base URL", text: $settings.baseURLString)
            Picker("Refresh interval", selection: $settings.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            Toggle("Enable CLI-backed controls", isOn: $settings.enableCLIControls)
            HStack {
                TextField("ollama CLI path", text: $settings.ollamaCLIPath)
                Button("Auto-detect") {
                    Task { await detectCLI() }
                }
            }
            Toggle("Show advanced service configuration notes", isOn: $settings.showAdvancedServiceNotes)
            Toggle("Read local Ollama logs", isOn: $settings.readLocalLogs)
            Toggle("Confirm before unloading models", isOn: $settings.confirmUnload)
            if !detectionStatus.isEmpty {
                Text(detectionStatus).foregroundStyle(.secondary)
            }
        }
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
