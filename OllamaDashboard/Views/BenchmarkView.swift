import SwiftUI

struct BenchmarkView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @State private var selectedModel = ""
    @State private var selectedProfileID: RuntimeProfile.ID?
    @State private var preset: BenchmarkPrompt = .tiny
    @State private var customPrompt = ""
    @State private var numCtx = 8192
    @State private var keepAlive = "5m"
    @State private var result: BenchmarkResult?
    @State private var status = ""
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Benchmark").font(.title3.bold())
            HStack {
                Picker("Model", selection: $selectedModel) {
                    Text("Select model").tag("")
                    ForEach(monitor.installedModels) { Text($0.name).tag($0.name) }
                }
                Picker("Profile", selection: $selectedProfileID) {
                    Text("None").tag(RuntimeProfile.ID?.none)
                    ForEach(profiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Apply") { applyProfile() }
            }
            HStack {
                Picker("Prompt", selection: $preset) {
                    ForEach(BenchmarkPrompt.allCases) { Text($0.label).tag($0) }
                }
                TextField("num_ctx", value: $numCtx, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("keep_alive", text: $keepAlive)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            if preset == .custom {
                TextEditor(text: $customPrompt)
                    .frame(height: 70)
                    .border(.quaternary)
            }
            Button(isRunning ? "Running..." : "Run Benchmark") {
                Task { await runBenchmark() }
            }
            .disabled(selectedModel.isEmpty || isRunning)

            if let result {
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(label: "Load time", value: DurationFormatter.nanoseconds(result.loadDuration))
                    InfoRow(label: "Prompt tokens", value: result.promptEvalCount.map(String.init) ?? "Unknown")
                    InfoRow(label: "Output tokens", value: result.evalCount.map(String.init) ?? "Unknown")
                    InfoRow(label: "Output tokens/sec", value: result.outputTokensPerSecond.map { String(format: "%.2f", $0) } ?? "Unknown")
                    InfoRow(label: "Total time", value: DurationFormatter.nanoseconds(result.totalDuration))
                    InfoRow(label: "Warm before run", value: result.wasAlreadyWarm ? "Likely yes" : "Likely no")
                }
            } else {
                Text(status.isEmpty ? "Timing stats are shown when Ollama includes them in the final response." : status)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onAppear {
            selectedModel = selectedModel.isEmpty ? monitor.installedModels.first?.name ?? "" : selectedModel
        }
    }

    private func applyProfile() {
        guard let id = selectedProfileID, let profile = profiles.profiles.first(where: { $0.id == id }) else { return }
        let applied = AppliedRuntimeProfile(profile: profile, currentModel: selectedModel)
        selectedModel = applied.model
        numCtx = applied.numCtx
        keepAlive = applied.keepAlive
    }

    private func runBenchmark() async {
        isRunning = true
        status = ""
        defer { isRunning = false }
        do {
            result = try await BenchmarkService(client: OllamaAPIClient(baseURL: settings.baseURL))
                .run(model: selectedModel, preset: preset, customPrompt: customPrompt, numCtx: numCtx, keepAlive: keepAlive)
        } catch {
            result = nil
            status = error.localizedDescription
        }
    }
}
