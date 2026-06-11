import AppKit
import SwiftUI

struct ModelsView: View {
    @ObservedObject var monitor: OllamaServiceMonitor

    var body: some View {
        InstalledModelsView(monitor: monitor)
    }
}

struct InstalledModelsView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var profiles: ProfileManager
    @EnvironmentObject private var proxy: OllamaProxyServer
    @State private var searchText = ""
    @State private var sort: InstalledModelSort = .name
    @State private var selectedModelID: InstalledModel.ID?
    @State private var selectedProfileID: RuntimeProfile.ID?
    @State private var detailModelID: InstalledModel.ID?
    @State private var detailSummary: ModelDetailSummary?
    @State private var detailError = ""
    @State private var warmStatus = ""
    @State private var isWarming = false
    @State private var isUnloading = false
    @State private var keepAlive = "30m"
    @State private var pendingUnload = PendingUnloadConfirmation()
    @State private var profileUsage = ModelProfileUsage()
    @State private var now = Date()

    private let keepAliveOptions = ["0", "5m", "30m", "1h", "24h", "-1"]
    private let warmCountdownTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var filteredModels: [InstalledModel] {
        InstalledModelListPolicy.filteredModels(
            monitor.installedModels,
            searchText: searchText,
            sort: sort
        )
    }

    var selectedModel: InstalledModel? {
        guard let selectedModelID else { return nil }
        return monitor.installedModels.first { $0.id == selectedModelID }
    }

    var selectedProfile: RuntimeProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.profiles.first { $0.id == selectedProfileID }
    }

    private var preferredNameWidth: CGFloat {
        ModelNameWidthPolicy.preferredNameWidth(for: filteredModels)
    }

    private var selectedModelStatus: ModelLoadStatus? {
        guard let selectedModel else { return nil }
        return ModelStatusPolicy.status(
            for: selectedModel,
            runningModels: monitor.runningModels,
            activeModelNames: proxy.activeModelNames,
            now: now
        )
    }

    private var selectedModelIsWarm: Bool {
        selectedModelStatus == .warm || selectedModelStatus == .busy
    }

    private var isModelActionRunning: Bool {
        isWarming || isUnloading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Models").font(.title3.bold())
                Spacer()
            }
            HStack(spacing: 8) {
                TextField("Filter models", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isModelActionRunning)
                Picker("Sort", selection: $sort) {
                    ForEach(InstalledModelSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 120)
                .disabled(isModelActionRunning)
                Button(detailsButtonTitle) {
                    Task { await toggleDetail() }
                }
                .disabled(!InstalledModelActionPolicy.canUseSelectionActions(
                    hasSelection: selectedModel != nil,
                    isWarming: isWarming,
                    isUnloading: isUnloading
                ))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Profile")
                    Picker("Profile", selection: $selectedProfileID) {
                        Text("None").tag(RuntimeProfile.ID?.none)
                        ForEach(profiles.profiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: 175)
                    .disabled(isModelActionRunning)

                    Text("Keep alive")
                    Picker("Keep alive", selection: $keepAlive) {
                        ForEach(keepAliveOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 82)
                    .disabled(isModelActionRunning)

                    if !warmStatus.isEmpty {
                        Text(warmStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button(modelActionButtonTitle) {
                        Task { await warmSelected() }
                    }
                    .disabled(!InstalledModelActionPolicy.canWarmSelected(
                        status: selectedModelStatus,
                        isWarming: isWarming,
                        isUnloading: isUnloading
                    ))
                    Button("Unload Selected") {
                        if settings.confirmUnload {
                            pendingUnload.begin(forModelName: selectedModel?.name)
                        } else {
                            Task { await unloadSelected() }
                        }
                    }
                    .disabled(!InstalledModelActionPolicy.canUnloadSelected(
                        isWarm: selectedModelIsWarm,
                        isWarming: isWarming,
                        isUnloading: isUnloading
                    ))
                    Button("Copy Model Name") {
                        if let name = selectedModel?.name {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(name, forType: .string)
                        }
                    }
                    .disabled(selectedModel == nil || isModelActionRunning)
                    Spacer()
                }
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
            if filteredModels.isEmpty {
                EmptyStateView(title: "No installed models", detail: "Install models with Ollama, then refresh.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredModels) { model in
                            let isSelected = selectedModelID == model.id
                            InstalledModelRow(
                                model: model,
                                status: ModelStatusPolicy.status(
                                    for: model,
                                    runningModels: monitor.runningModels,
                                    activeModelNames: proxy.activeModelNames,
                                    now: now
                                ),
                                timeRemaining: ModelStatusPolicy.timeRemaining(
                                    for: ModelStatusPolicy.runningModel(
                                        for: model,
                                        runningModels: monitor.runningModels,
                                        now: now
                                    ),
                                    now: now
                                ),
                                profileName: profileUsage.profileName(for: model.name),
                                preferredNameWidth: preferredNameWidth,
                                isSelected: isSelected
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.85))
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isModelActionRunning else { return }
                                selectedModelID = model.id
                            }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                guard !isModelActionRunning else { return }
                                Task { await toggleDetail(for: model) }
                            })
                            Divider()
                                .opacity(isSelected ? 0 : 1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .disabled(isModelActionRunning)
                .frame(
                    minHeight: detailSummary == nil ? 230 : 150,
                    maxHeight: detailSummary == nil ? 340 : 190
                )
                if let detailSummary {
                    ScrollView {
                        ModelDetailSummaryView(summary: detailSummary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }
                }
                if !detailError.isEmpty {
                    Text(detailError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: selectedModelID) { _ in
            detailModelID = nil
            detailSummary = nil
            detailError = ""
            pendingUnload.cancel()
        }
        .onChange(of: selectedProfileID) { _ in
            guard !isModelActionRunning else { return }
            if let preferredModelID = PreferredModelSelectionPolicy.selectedInstalledModelID(
                for: selectedProfile,
                installedModels: monitor.installedModels
            ) {
                selectedModelID = preferredModelID
            }
        }
        .onReceive(warmCountdownTimer) { tick in
            now = tick
        }
    }

    private var isShowingDetailForSelection: Bool {
        selectedModelID != nil && selectedModelID == detailModelID && detailSummary != nil
    }

    private var detailsButtonTitle: String {
        isShowingDetailForSelection ? "Hide Details" : "Details"
    }

    private var modelActionButtonTitle: String {
        if isWarming { return "Warming..." }
        if isUnloading { return "Unloading..." }
        return "Warm Up Selected"
    }

    private func toggleDetail() async {
        guard let selectedModel else { return }
        await toggleDetail(for: selectedModel)
    }

    private func toggleDetail(for model: InstalledModel) async {
        selectedModelID = model.id
        if InstalledModelDetailToggle.shouldHideDetails(
            selectedModelID: selectedModelID,
            detailModelID: detailModelID,
            hasDetailSummary: detailSummary != nil,
            targetModelID: model.id
        ) {
            hideDetail()
        } else {
            await loadDetail(for: model)
        }
    }

    private func hideDetail() {
        detailModelID = nil
        detailSummary = nil
        detailError = ""
    }

    private func loadDetail(for model: InstalledModel) async {
        do {
            let detail = try await OllamaAPIClient(baseURL: settings.baseURL).showModel(name: model.name)
            detailModelID = model.id
            detailSummary = ModelDetailSummary(detail: detail)
            detailError = ""
        } catch {
            detailModelID = nil
            detailSummary = nil
            detailError = error.localizedDescription
        }
    }

    private func warmSelected() async {
        guard let selectedModel, !isModelActionRunning else { return }
        isWarming = true

        let modelMaxContext = selectedProfile == nil ? nil : await loadModelMaxContext(model: selectedModel.name)
        let request = ModelWarmRequest.resolve(
            selectedModelName: selectedModel.name,
            profile: selectedProfile,
            modelMaxContext: modelMaxContext,
            defaultKeepAlive: keepAlive
        )
        let message = await monitor.warm(
            model: request.model,
            keepAlive: request.keepAlive,
            numCtx: request.numCtx,
            options: request.options
        )
        if message.hasPrefix("Warmed") {
            profileUsage.record(profile: selectedProfile, fallbackModel: selectedModel.name)
            warmStatus = "Warmed \(request.model) with \(request.statusDetail)"
            await waitForInstalledModel(named: request.model, toBecome: .warm)
        } else {
            warmStatus = message
        }
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
        warmStatus = message
        if message.hasPrefix("Unloaded") || message.hasPrefix("Stopped") {
            await waitForInstalledModel(named: modelName, toBecome: .cold)
        }
        isUnloading = false
    }

    private func waitForInstalledModel(named modelName: String, toBecome targetStatus: ModelLoadStatus) async {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let snapshotTime = Date()
            now = snapshotTime
            if ModelLifecycleTransitionPolicy.installedModelReached(
                modelName: modelName,
                targetStatus: targetStatus,
                installedModels: monitor.installedModels,
                runningModels: monitor.runningModels,
                activeModelNames: proxy.activeModelNames,
                now: snapshotTime
            ) {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await monitor.refreshAll()
        }
    }

    private func loadModelMaxContext(model: String) async -> Int? {
        guard !model.isEmpty else { return nil }
        do {
            let detail = try await OllamaAPIClient(baseURL: settings.baseURL).showModel(name: model)
            return ModelContextMetadata(detail: detail).maxContextLength
        } catch {
            warmStatus = "Could not load context metadata for \(model): \(error.localizedDescription)"
            return nil
        }
    }
}
