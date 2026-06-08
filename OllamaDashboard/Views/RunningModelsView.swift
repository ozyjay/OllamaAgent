import SwiftUI

struct RunningModelsView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedModelID: RunningModel.ID?
    @State private var keepAlive = "30m"
    @State private var status = ""
    @State private var showUnloadConfirmation = false

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
                            showUnloadConfirmation = true
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
                if !status.isEmpty {
                    Text(status).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .confirmationDialog("Unload selected model?", isPresented: $showUnloadConfirmation) {
            Button("Unload", role: .destructive) {
                Task { await unloadSelected() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func warmSelected() async {
        guard let name = selectedModel?.name else { return }
        status = await monitor.warm(model: name, keepAlive: keepAlive, numCtx: nil)
    }

    private func unloadSelected() async {
        guard let name = selectedModel?.name else { return }
        status = await monitor.unload(model: name)
    }
}
