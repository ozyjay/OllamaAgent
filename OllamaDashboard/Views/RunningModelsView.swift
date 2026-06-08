import SwiftUI

struct RunningModelsView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @State private var selectedModelID: RunningModel.ID?
    @State private var selectedProfileID: RuntimeProfile.ID?
    @State private var keepAlive = "30m"
    @State private var numCtx: Int?
    @State private var status = ""
    @State private var pendingUnload = PendingUnloadConfirmation()

    private let keepAliveOptions = ["0", "5m", "30m", "1h", "24h", "-1"]

    private var selectedModel: RunningModel? {
        guard let selectedModelID else { return nil }
        return monitor.runningModels.first { $0.id == selectedModelID }
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
                Button("Apply") { applyProfile() }
                    .disabled(selectedProfileID == nil)
                Picker("Keep alive", selection: $keepAlive) {
                    ForEach(keepAliveOptions, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 140)
                Button("Refresh") { Task { await monitor.refreshAll() } }
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
                HStack {
                    Button("Warm Selected") {
                        Task { await warmSelected() }
                    }
                    .disabled(selectedModel == nil)
                    Button("Unload Selected") {
                        if settings.confirmUnload {
                            pendingUnload.begin(for: selectedModel)
                        } else {
                            Task { await unloadSelected() }
                        }
                    }
                    .disabled(selectedModel == nil)
                    Button("Copy Model Name") {
                        if let name = selectedModel?.name {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(name, forType: .string)
                        }
                    }
                    .disabled(selectedModel == nil)
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
                        Button("Cancel") {
                            pendingUnload.cancel()
                        }
                    }
                }
                if !status.isEmpty {
                    Text(status).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    private func warmSelected() async {
        guard let name = selectedModel?.name else { return }
        status = await monitor.warm(model: name, keepAlive: keepAlive, numCtx: numCtx)
    }

    private func unloadSelected() async {
        guard let name = selectedModel?.name else { return }
        await unload(modelName: name)
    }

    private func unload(modelName: String) async {
        status = await monitor.unload(model: modelName)
    }

    private func applyProfile() {
        guard let id = selectedProfileID, let profile = profiles.profiles.first(where: { $0.id == id }) else { return }
        let applied = AppliedRuntimeProfile(profile: profile, currentModel: selectedModel?.name ?? "")
        keepAlive = applied.keepAlive
        numCtx = applied.numCtx
        if let runningModel = monitor.runningModels.first(where: { $0.name == applied.model }) {
            selectedModelID = runningModel.id
        }
        status = "Applied \(profile.name): keep_alive \(applied.keepAlive), num_ctx \(applied.numCtx)."
    }
}

struct PendingUnloadConfirmation {
    private(set) var modelName: String?

    var isPresented: Bool {
        modelName != nil
    }

    mutating func begin(for model: RunningModel?) {
        modelName = model?.name
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
