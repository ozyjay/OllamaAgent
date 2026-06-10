import SwiftUI

private enum WorkbenchToolSection: String, CaseIterable, Identifiable {
    case prompt
    case benchmark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .prompt: return "Prompt"
        case .benchmark: return "Benchmark"
        }
    }
}

struct WorkbenchView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @State private var selectedSection: WorkbenchToolSection = .prompt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Workbench tools", selection: $selectedSection) {
                ForEach(WorkbenchToolSection.allCases) { section in
                    Text(section.label).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch selectedSection {
            case .prompt:
                ContextView(monitor: monitor)
            case .benchmark:
                BenchmarkView(monitor: monitor)
            }
        }
    }
}

struct ContextView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @State private var selectedModel = ""
    @State private var selectedProfileID: RuntimeProfile.ID?
    @State private var numCtx = 8192
    @State private var customCtx = "8192"
    @State private var useModelDefaultContext = false
    @State private var prompt = "Reply with one sentence."
    @State private var keepAlive = "5m"
    @State private var generationOptions: [String: JSONValue] = [:]
    @State private var result = ""
    @State private var isRunning = false

    private let presets = [4096, 8192, 16384, 32768, 65536, 131072]
    private let keepAliveOptions = ["0", "5m", "30m", "1h", "24h", "-1"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context Control").font(.title3.bold())
            HStack {
                Picker("Model", selection: $selectedModel) {
                    Text("Select model").tag("")
                    ForEach(monitor.installedModels) { Text($0.name).tag($0.name) }
                }
                Picker("Profile", selection: $selectedProfileID) {
                    Text("None").tag(RuntimeProfile.ID?.none)
                    ForEach(profiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Apply") { Task { await applyProfile() } }
            }
            HStack {
                Picker("Context", selection: contextSelection) {
                    ForEach(presets, id: \.self) { Text("\($0)").tag($0) }
                }
                TextField("Custom", text: $customCtx)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Button("Use Custom") {
                    if let value = Int(customCtx), value > 0 {
                        numCtx = value
                        useModelDefaultContext = false
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
                Text(result.isEmpty ? "Profiles are model-aware app-side presets. Running a test prompt does not change the already-running Ollama service configuration." : result)
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

    private var contextSelection: Binding<Int> {
        Binding(
            get: { numCtx },
            set: {
                numCtx = $0
                customCtx = "\($0)"
                useModelDefaultContext = false
            }
        )
    }

    private func applyProfile() async {
        guard let id = selectedProfileID, let profile = profiles.profiles.first(where: { $0.id == id }) else { return }
        let targetModel = profile.resolvedModel(currentModel: selectedModel)
        let modelMaxContext = await loadModelMaxContext(model: targetModel)
        let applied = AppliedRuntimeProfile(profile: profile, currentModel: selectedModel, modelMaxContext: modelMaxContext)
        selectedModel = applied.model
        if let resolvedNumCtx = applied.numCtx {
            numCtx = resolvedNumCtx
            customCtx = "\(resolvedNumCtx)"
            useModelDefaultContext = false
        } else {
            useModelDefaultContext = true
        }
        keepAlive = applied.keepAlive
        generationOptions = applied.options
        result = "Applied \(profile.name): \(applied.contextStatus)"
    }

    private func loadModelMaxContext(model: String) async -> Int? {
        guard !model.isEmpty else { return nil }
        do {
            let detail = try await OllamaAPIClient(baseURL: settings.baseURL).showModel(name: model)
            return ModelContextMetadata(detail: detail).maxContextLength
        } catch {
            result = "Could not load context metadata for \(model): \(error.localizedDescription)"
            return nil
        }
    }

    private func runPrompt() async {
        isRunning = true
        defer { isRunning = false }
        do {
            let benchmark = try await OllamaAPIClient(baseURL: settings.baseURL)
                .runBenchmark(
                    model: selectedModel,
                    prompt: prompt,
                    numCtx: useModelDefaultContext ? nil : numCtx,
                    keepAlive: keepAlive,
                    options: generationOptions
                )
            result = benchmark.response
        } catch {
            result = error.localizedDescription
        }
    }
}
