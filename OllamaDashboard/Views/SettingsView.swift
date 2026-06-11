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
                GridRow {
                    Spacer()
                    Toggle("Enable local Ollama proxy", isOn: $settings.enableProxy)
                }
                GridRow {
                    Text("Proxy port")
                    TextField(
                        "Proxy port",
                        value: $settings.proxyPort,
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120, alignment: .leading)
                }
                GridRow {
                    Spacer()
                    Toggle("Enable prompt guardrails", isOn: $settings.enablePromptGuardrails)
                }
                GridRow {
                    Text("Guardrail response")
                    Picker("Guardrail response", selection: $settings.promptGuardrailResponseMode) {
                        ForEach(PromptGuardrailResponseMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190, alignment: .leading)
                }
                GridRow {
                    Text("Warn prompt chars")
                    thresholdField(value: $settings.promptGuardrailWarnPromptCharacters)
                }
                GridRow {
                    Text("Block prompt chars")
                    thresholdField(value: $settings.promptGuardrailBlockPromptCharacters)
                }
                GridRow {
                    Text("Warn body bytes")
                    thresholdField(value: $settings.promptGuardrailWarnBodyBytes)
                }
                GridRow {
                    Text("Block body bytes")
                    thresholdField(value: $settings.promptGuardrailBlockBodyBytes)
                }
                GridRow {
                    Text("Warn messages")
                    thresholdField(value: $settings.promptGuardrailWarnMessages)
                }
                GridRow {
                    Text("Block messages")
                    thresholdField(value: $settings.promptGuardrailBlockMessages)
                }
                GridRow {
                    Text("Warn context ratio")
                    ratioField(value: $settings.promptGuardrailWarnContextRatio)
                }
                GridRow {
                    Text("Block context ratio")
                    ratioField(value: $settings.promptGuardrailBlockContextRatio)
                }
            }
            Toggle("Show advanced service configuration notes", isOn: $settings.showAdvancedServiceNotes)
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

    private func thresholdField(value: Binding<Int>) -> some View {
        TextField("Threshold", value: value, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .frame(width: 140, alignment: .leading)
    }

    private func ratioField(value: Binding<Double>) -> some View {
        TextField("Ratio", value: value, format: .number.precision(.fractionLength(2)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 100, alignment: .leading)
    }
}
