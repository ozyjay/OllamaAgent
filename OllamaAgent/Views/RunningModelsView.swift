import SwiftUI

struct RunningModelsView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @State private var selectedModelID: RunningModel.ID?
    @State private var selectedProfileID: RuntimeProfile.ID?
    @State private var keepAlive = "30m"
    @State private var numCtx: Int?
    @State private var generationOptions: [String: JSONValue] = [:]
    @State private var status = ""
    @State private var pendingUnload = PendingUnloadConfirmation()
    @State private var isWarming = false
    @State private var isUnloading = false

    private let keepAliveOptions = ["0", "5m", "30m", "1h", "24h", "-1"]

    private var selectedModel: RunningModel? {
        guard let selectedModelID else { return nil }
        return monitor.runningModels.first { $0.id == selectedModelID }
    }

    private var isModelActionRunning: Bool {
        isWarming || isUnloading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Running Models").font(.title3.bold())
                Spacer()
                Picker("Profile", selection: $selectedProfileID) {
                    Text("None").tag(RuntimeProfile.ID?.none)
                    ForEach(profiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
                .frame(width: 190)
                .disabled(isModelActionRunning)
                Button("Apply") { Task { await applyProfile() } }
                    .disabled(selectedProfileID == nil || isModelActionRunning)
                Picker("Keep alive", selection: $keepAlive) {
                    ForEach(keepAliveOptions, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 140)
                .disabled(isModelActionRunning)
                Button("Refresh") { Task { await monitor.refreshAll() } }
                    .disabled(isModelActionRunning)
            }
            if monitor.runningModels.isEmpty {
                EmptyStateView(title: "No loaded models", detail: "Warm an installed model or run an Ollama request.")
            } else {
                Table(monitor.runningModels, selection: $selectedModelID) {
                    TableColumn("Name") { Text($0.name).textSelection(.enabled) }
                    TableColumn("Size") { Text(ByteFormatter.string(from: $0.size)) }
                    TableColumn("VRAM") { Text(ByteFormatter.string(from: $0.sizeVRAM)) }
                    TableColumn("Expires") { Text(DurationFormatter.date($0.expiresAt)) }
                    TableColumn("Digest") { Text($0.digest ?? "Unknown").lineLimit(1) }
                }
                .frame(minHeight: 250)
                .disabled(isModelActionRunning)
                HStack {
                    Button(modelActionButtonTitle) {
                        Task { await warmSelected() }
                    }
                    .disabled(selectedModel == nil || isModelActionRunning)
                    Button("Unload Selected") {
                        if settings.confirmUnload {
                            pendingUnload.begin(for: selectedModel)
                        } else {
                            Task { await unloadSelected() }
                        }
                    }
                    .disabled(selectedModel == nil || isModelActionRunning)
                    Button("Copy Model Name") {
                        if let name = selectedModel?.name {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(name, forType: .string)
                        }
                    }
                    .disabled(selectedModel == nil || isModelActionRunning)
                    Spacer()
                }
                if pendingUnload.isPresented, let modelName = pendingUnload.modelName {
                    HStack {
                        Text("Unload \(modelName)?")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Unload", role: .destructive) {
                            if let name = pendingUnload.confirm() {
                                Task { await unload(modelName: name) }
                            }
                        }
                        .disabled(isModelActionRunning)
                        Button("Cancel") {
                            pendingUnload.cancel()
                        }
                        .disabled(isModelActionRunning)
                    }
                }
                if !status.isEmpty {
                    Text(status).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private var modelActionButtonTitle: String {
        if isWarming { return "Warming..." }
        if isUnloading { return "Unloading..." }
        return "Warm Again"
    }

    private func warmSelected() async {
        guard let name = selectedModel?.name, !isModelActionRunning else { return }
        isWarming = true
        let message = await monitor.warm(model: name, keepAlive: keepAlive, numCtx: numCtx, options: generationOptions)
        status = message.hasPrefix("Warmed") ? "Warmed \(name) with keep_alive \(keepAlive)." : message
        isWarming = false
    }

    private func unloadSelected() async {
        guard let name = selectedModel?.name else { return }
        await unload(modelName: name)
    }

    private func unload(modelName: String) async {
        guard !isModelActionRunning else { return }
        isUnloading = true
        let message = await monitor.unload(model: modelName)
        status = message
        if message.hasPrefix("Unloaded") || message.hasPrefix("Stopped") {
            await waitForRunningModelToDisappear(named: modelName)
        }
        isUnloading = false
    }

    private func waitForRunningModelToDisappear(named modelName: String) async {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if ModelLifecycleTransitionPolicy.runningModelIsAbsent(
                modelName: modelName,
                runningModels: monitor.runningModels,
                now: Date()
            ) {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await monitor.refreshAll()
        }
    }

    private func applyProfile() async {
        guard !isModelActionRunning else { return }
        guard let id = selectedProfileID, let profile = profiles.profiles.first(where: { $0.id == id }) else { return }
        let currentModel = selectedModel?.name ?? ""
        let targetModel = profile.resolvedModel(currentModel: currentModel)
        let modelMaxContext = await loadModelMaxContext(model: targetModel)
        let applied = AppliedRuntimeProfile(profile: profile, currentModel: currentModel, modelMaxContext: modelMaxContext)
        keepAlive = applied.keepAlive
        numCtx = applied.numCtx
        generationOptions = applied.options
        if let runningModel = monitor.runningModels.first(where: { $0.name == applied.model }) {
            selectedModelID = runningModel.id
        }
        status = "Applied \(profile.name): keep_alive \(applied.keepAlive), \(applied.contextStatus)"
    }

    private func loadModelMaxContext(model: String) async -> Int? {
        guard !model.isEmpty else { return nil }
        do {
            let detail = try await OllamaAPIClient(baseURL: settings.baseURL).showModel(name: model)
            return ModelContextMetadata(detail: detail).maxContextLength
        } catch {
            status = "Could not load context metadata for \(model): \(error.localizedDescription)"
            return nil
        }
    }
}

struct PendingUnloadConfirmation {
    private(set) var modelName: String?

    var isPresented: Bool {
        modelName != nil
    }

    mutating func begin(for model: RunningModel?) {
        begin(forModelName: model?.name)
    }

    mutating func begin(forModelName name: String?) {
        modelName = name
    }

    mutating func cancel() {
        modelName = nil
    }

    mutating func confirm() -> String? {
        let confirmedModelName = modelName
        modelName = nil
        return confirmedModelName
    }
}
