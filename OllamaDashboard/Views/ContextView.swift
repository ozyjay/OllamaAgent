import SwiftUI

struct ContextView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedModel = ""
    @State private var numCtx = 8192
    @State private var customCtx = "8192"
    @State private var prompt = "Reply with one sentence."
    @State private var keepAlive = "5m"
    @State private var result = ""
    @State private var isRunning = false

    private let presets = [4096, 8192, 16384, 32768, 65536, 131072]
    private let keepAliveOptions = ["0", "5m", "30m", "1h", "24h", "-1"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context Control").font(.title3.bold())
            Picker("Model", selection: $selectedModel) {
                Text("Select model").tag("")
                ForEach(monitor.installedModels) { Text($0.name).tag($0.name) }
            }
            HStack {
                Picker("Context", selection: $numCtx) {
                    ForEach(presets, id: \.self) { Text("\($0)").tag($0) }
                }
                TextField("Custom", text: $customCtx)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("Use Custom") {
                    if let value = Int(customCtx), value > 0 {
                        numCtx = value
                    }
                }
                Picker("Keep Alive", selection: $keepAlive) {
                    ForEach(keepAliveOptions, id: \.self) { Text($0).tag($0) }
                }
            }
            TextEditor(text: $prompt)
                .font(.body)
                .frame(height: 90)
                .border(.quaternary)
            Button(isRunning ? "Running..." : "Run Test Prompt") {
                Task { await runPrompt() }
            }
            .disabled(selectedModel.isEmpty || isRunning)
            ScrollView {
                Text(result.isEmpty ? "Profiles are app-side presets. Running a test prompt does not change the already-running Ollama service configuration." : result)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .foregroundStyle(result.isEmpty ? .secondary : .primary)
            }
        }
        .onAppear {
            if selectedModel.isEmpty {
                selectedModel = monitor.installedModels.first?.name ?? ""
            }
        }
    }

    private func runPrompt() async {
        isRunning = true
        defer { isRunning = false }
        do {
            let benchmark = try await OllamaAPIClient(baseURL: settings.baseURL)
                .runBenchmark(model: selectedModel, prompt: prompt, numCtx: numCtx, keepAlive: keepAlive)
            result = benchmark.response
        } catch {
            result = error.localizedDescription
        }
    }
}
