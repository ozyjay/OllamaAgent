import AppKit
import SwiftUI

struct ModelsView: View {
    @ObservedObject var monitor: OllamaServiceMonitor

    var body: some View {
        InstalledModelsView(monitor: monitor)
    }
}

struct ModelWarmRequest: Equatable {
    let model: String
    let keepAlive: String
    let numCtx: Int?
    let options: [String: JSONValue]
    let statusDetail: String

    static func resolve(
        selectedModelName: String,
        profile: RuntimeProfile?,
        modelMaxContext: Int?,
        defaultKeepAlive: String = "30m"
    ) -> ModelWarmRequest {
        guard let profile else {
            return ModelWarmRequest(
                model: selectedModelName,
                keepAlive: defaultKeepAlive,
                numCtx: nil,
                options: [:],
                statusDetail: "keep_alive \(defaultKeepAlive), model default context."
            )
        }

        let selectedModelProfile = RuntimeProfile(
            id: profile.id,
            name: profile.name,
            preferredModel: "",
            contextPolicy: profile.contextPolicy,
            contextOverrides: profile.contextOverrides,
            keepAlive: profile.keepAlive,
            numPredict: profile.numPredict,
            temperature: profile.temperature,
            generationOptions: profile.generationOptions,
            notes: profile.notes,
            purpose: profile.purpose
        )
        let applied = AppliedRuntimeProfile(
            profile: selectedModelProfile,
            currentModel: selectedModelName,
            modelMaxContext: modelMaxContext
        )
        return ModelWarmRequest(
            model: applied.model,
            keepAlive: applied.keepAlive,
            numCtx: applied.numCtx,
            options: applied.options,
            statusDetail: "keep_alive \(applied.keepAlive), \(warmContextStatus(from: applied.contextStatus))"
        )
    }

    private static func warmContextStatus(from contextStatus: String) -> String {
        switch contextStatus {
        case "Using Ollama model default context.":
            return "model default context."
        default:
            return contextStatus
                .replacingOccurrences(of: " from low ram policy.", with: " from profile policy.")
                .replacingOccurrences(of: " from balanced policy.", with: " from profile policy.")
                .replacingOccurrences(of: " from max known policy.", with: " from profile policy.")
        }
    }
}

enum InstalledModelSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Size"
    case modified = "Modified"
    var id: String { rawValue }
}

enum InstalledModelListPolicy {
    static func filteredModels(
        _ models: [InstalledModel],
        searchText: String,
        sort: InstalledModelSort
    ) -> [InstalledModel] {
        let filtered = models.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        switch sort {
        case .name: return filtered.sorted { $0.name < $1.name }
        case .size: return filtered.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .modified: return filtered.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        }
    }
}

enum ModelLoadStatus: String, Equatable {
    case idle = "Idle"
    case warm = "Warm"
    case busy = "Busy"
}

struct ModelStatusRow: Equatable {
    let modelName: String
    let status: ModelLoadStatus
    let timeRemaining: String?
}

enum ModelStatusPolicy {
    static func runningModel(for model: InstalledModel, runningModels: [RunningModel]) -> RunningModel? {
        runningModels.first { namesMatch($0.name, model.name) || namesMatch($0.model, model.name) }
    }

    static func isActive(model: InstalledModel, runningModels: [RunningModel], activeModelNames: Set<String>) -> Bool {
        activeModelNames.contains { activeName in
            namesMatch(activeName, model.name)
                || runningModel(for: model, runningModels: runningModels).map {
                    namesMatch(activeName, $0.name) || namesMatch(activeName, $0.model)
                } == true
        }
    }

    static func status(
        for model: InstalledModel,
        runningModels: [RunningModel],
        activeModelNames: Set<String> = []
    ) -> ModelLoadStatus {
        if isActive(model: model, runningModels: runningModels, activeModelNames: activeModelNames) {
            return .busy
        }
        return runningModel(for: model, runningModels: runningModels) == nil ? .idle : .warm
    }

    static func timeRemaining(for runningModel: RunningModel?, now: Date = Date()) -> String? {
        guard let expiresAt = runningModel?.expiresAt else { return nil }
        return WarmTimeRemainingFormatter.string(from: max(0, expiresAt.timeIntervalSince(now)))
    }

    static func statusRows(
        installedModels: [InstalledModel],
        runningModels: [RunningModel],
        activeModelNames: Set<String> = [],
        now: Date = Date()
    ) -> [ModelStatusRow] {
        installedModels.map { model in
            let runningModel = runningModel(for: model, runningModels: runningModels)
            return ModelStatusRow(
                modelName: model.name,
                status: isActive(model: model, runningModels: runningModels, activeModelNames: activeModelNames)
                    ? .busy
                    : (runningModel == nil ? .idle : .warm),
                timeRemaining: timeRemaining(for: runningModel, now: now)
            )
        }
    }

    private static func namesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        return normalizedName(lhs) == normalizedName(rhs)
    }

    private static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(":latest") ? String(trimmed.dropLast(":latest".count)) : trimmed
    }
}

enum WarmTimeRemainingFormatter {
    static func string(from seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        return "\(seconds)s"
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
            activeModelNames: proxy.activeModelNames
        )
    }

    private var selectedModelIsWarm: Bool {
        selectedModelStatus == .warm || selectedModelStatus == .busy
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
                Picker("Sort", selection: $sort) {
                    ForEach(InstalledModelSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 120)
                Button(detailsButtonTitle) {
                    Task { await toggleDetail() }
                }
                .disabled(selectedModel == nil)
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

                    Text("Keep alive")
                    Picker("Keep alive", selection: $keepAlive) {
                        ForEach(keepAliveOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 82)

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
                    Button(isWarming ? "Warming..." : "Warm Up Selected") {
                        Task { await warmSelected() }
                    }
                    .disabled(selectedModel == nil || isWarming)
                    Button("Unload Selected") {
                        if settings.confirmUnload {
                            pendingUnload.begin(forModelName: selectedModel?.name)
                        } else {
                            Task { await unloadSelected() }
                        }
                    }
                    .disabled(!selectedModelIsWarm)
                    Button("Copy Model Name") {
                        if let name = selectedModel?.name {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(name, forType: .string)
                        }
                    }
                    .disabled(selectedModel == nil)
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
                    Button("Cancel") {
                        pendingUnload.cancel()
                    }
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
                                    activeModelNames: proxy.activeModelNames
                                ),
                                timeRemaining: ModelStatusPolicy.timeRemaining(
                                    for: ModelStatusPolicy.runningModel(for: model, runningModels: monitor.runningModels),
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
                                selectedModelID = model.id
                            }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
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
        guard let selectedModel else { return }
        isWarming = true
        defer { isWarming = false }

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
            warmStatus = "\(message) \(request.statusDetail)"
        } else {
            warmStatus = message
        }
    }

    private func unloadSelected() async {
        guard let name = selectedModel?.name else { return }
        await unload(modelName: name)
    }

    private func unload(modelName: String) async {
        warmStatus = await monitor.unload(model: modelName)
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

struct InstalledModelDetailToggle {
    static func shouldHideDetails(
        selectedModelID: InstalledModel.ID?,
        detailModelID: InstalledModel.ID?,
        hasDetailSummary: Bool,
        targetModelID: InstalledModel.ID
    ) -> Bool {
        selectedModelID == targetModelID && detailModelID == targetModelID && hasDetailSummary
    }
}

private struct InstalledModelRow: View {
    let model: InstalledModel
    let status: ModelLoadStatus
    let timeRemaining: String?
    let profileName: String?
    let preferredNameWidth: CGFloat
    let isSelected: Bool
    private var summary: InstalledModelRowSummary {
        InstalledModelRowSummary(model: model)
    }
    private var metadataText: String {
        summary.metadata
    }
    private var profileText: String {
        profileName.map { "Profile: \($0)" } ?? "Profile: Not warmed"
    }

    var body: some View {
        ModelRowAdaptiveLayout(spacing: 12, minimumFieldsWidth: 360, idealNameWidth: preferredNameWidth) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(status.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status == .idle ? (isSelected ? .white.opacity(0.9) : .secondary) : (isSelected ? .white : .green))
                        .lineLimit(1)
                    Text(timeRemaining ?? "")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                        .lineLimit(1)
                        .opacity(timeRemaining == nil ? 0 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Text(profileText)
                    .font(.caption.weight(profileName == nil ? .regular : .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : (profileName == nil ? .secondary : .primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(summary.trailingPrimary)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(summary.trailingSecondary ?? "")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(summary.trailingSecondary == nil ? 0 : 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

struct ModelProfileUsage: Equatable {
    private var namesByModel: [String: String] = [:]

    mutating func record(profile: RuntimeProfile?, fallbackModel: String) {
        namesByModel[fallbackModel] = profile?.name ?? "No profile"
    }

    func profileName(for model: String) -> String? {
        namesByModel[model]
    }
}

struct ModelRowNameWidths: Equatable {
    let nameWidth: CGFloat
    let fieldsWidth: CGFloat
}

enum ModelRowNameSizing {
    static func widths(
        availableWidth: CGFloat,
        idealNameWidth: CGFloat,
        minimumFieldsWidth: CGFloat,
        spacing: CGFloat
    ) -> ModelRowNameWidths {
        let usableWidth = max(0, availableWidth - spacing)
        guard usableWidth > 0 else {
            return ModelRowNameWidths(nameWidth: 0, fieldsWidth: 0)
        }

        let nameWidth = min(idealNameWidth, max(0, usableWidth - minimumFieldsWidth))
        return ModelRowNameWidths(
            nameWidth: nameWidth,
            fieldsWidth: max(0, usableWidth - nameWidth)
        )
    }
}

enum ModelNameWidthPolicy {
    static func preferredNameWidth(
        for models: [InstalledModel],
        measuring: (String) -> CGFloat = { modelName in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.preferredFont(forTextStyle: .body)
            ]
            return ceil((modelName as NSString).size(withAttributes: attributes).width)
        }
    ) -> CGFloat {
        models.map { measuring($0.name) }.max() ?? 0
    }
}

private struct ModelRowAdaptiveLayout: Layout {
    var spacing: CGFloat
    var minimumFieldsWidth: CGFloat
    var idealNameWidth: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }

        let proposedWidth = proposal.width ?? idealWidth(for: subviews)
        let widths = widths(in: proposedWidth, subviews: subviews)
        let nameSize = subviews[0].sizeThatFits(ProposedViewSize(width: widths.nameWidth, height: proposal.height))
        let fieldsSize = subviews[1].sizeThatFits(ProposedViewSize(width: widths.fieldsWidth, height: proposal.height))

        return CGSize(width: proposedWidth, height: max(nameSize.height, fieldsSize.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }

        let widths = widths(in: bounds.width, subviews: subviews)
        let nameProposal = ProposedViewSize(width: widths.nameWidth, height: bounds.height)
        let fieldsProposal = ProposedViewSize(width: widths.fieldsWidth, height: bounds.height)
        let nameSize = subviews[0].sizeThatFits(nameProposal)
        let fieldsSize = subviews[1].sizeThatFits(fieldsProposal)

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY - nameSize.height / 2),
            proposal: nameProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - widths.fieldsWidth, y: bounds.midY - fieldsSize.height / 2),
            proposal: fieldsProposal
        )
    }

    private func widths(in availableWidth: CGFloat, subviews: Subviews) -> ModelRowNameWidths {
        ModelRowNameSizing.widths(
            availableWidth: availableWidth,
            idealNameWidth: idealNameWidth ?? subviews[0].sizeThatFits(.unspecified).width,
            minimumFieldsWidth: minimumFieldsWidth,
            spacing: spacing
        )
    }

    private func idealWidth(for subviews: Subviews) -> CGFloat {
        subviews[0].sizeThatFits(.unspecified).width
            + spacing
            + subviews[1].sizeThatFits(.unspecified).width
    }
}

struct InstalledModelRowSummary: Equatable {
    let metadata: String
    let trailingPrimary: String
    let trailingSecondary: String?

    init(model: InstalledModel) {
        let diskSize = ByteFormatter.string(from: model.size)
        let shortDigest = model.digest?.trimmedNonEmpty.map { String($0.prefix(12)) }
        metadata = [
            DurationFormatter.date(model.modifiedAt),
            shortDigest
        ].compactMap { value in
            value == "Unknown" ? nil : value
        }.joined(separator: "  |  ")

        if let parameterSize = model.details?.parameterSize.trimmedNonEmpty
            ?? ParameterSizeInference.value(from: model.name) {
            trailingPrimary = parameterSize
            trailingSecondary = diskSize == "Unknown" ? nil : diskSize
        } else {
            trailingPrimary = diskSize
            trailingSecondary = nil
        }
    }
}

struct ParameterSizeInference {
    static func value(from modelName: String) -> String? {
        let pattern = #"(^|[:/_-])(\d+(?:\.\d+)?)([bBmM])(?=$|[:/_-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(modelName.startIndex..<modelName.endIndex, in: modelName)
        guard let match = regex.firstMatch(in: modelName, range: range),
              let numberRange = Range(match.range(at: 2), in: modelName),
              let unitRange = Range(match.range(at: 3), in: modelName)
        else {
            return nil
        }
        return "\(modelName[numberRange])\(modelName[unitRange].uppercased())"
    }
}

struct ModelDetailField: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
}

struct ModelDetailSection: Equatable, Identifiable {
    var id: String { title }
    let title: String
    let value: String
}

struct ModelDetailSummary: Equatable {
    let fields: [ModelDetailField]
    let sections: [ModelDetailSection]

    init(detail: ModelDetail) {
        let generationOptions = ProfileGenerationOptions(modelParameters: detail.parameters)
        fields = [
            Self.field("Format", detail.details?.format),
            Self.field("Family", detail.details?.family ?? detail.details?.families?.joined(separator: ", ")),
            Self.field("Parameters", detail.details?.parameterSize),
            Self.field("Quantization", detail.details?.quantizationLevel),
            Self.field("License", detail.license?.firstLine)
        ].compactMap(\.self) + generationOptions.valueRows().map { row in
            ModelDetailField(label: row.label, value: row.value)
        }

        sections = [
            Self.section("Modelfile", detail.modelfile),
            Self.section("Parameters", detail.parameters),
            Self.section("Template", detail.template)
        ].compactMap(\.self)
    }

    private static func field(_ label: String, _ value: String?) -> ModelDetailField? {
        guard let value = value.trimmedNonEmpty else { return nil }
        return ModelDetailField(label: label, value: value)
    }

    private static func section(_ title: String, _ value: String?) -> ModelDetailSection? {
        guard let value = value.trimmedNonEmpty else { return nil }
        return ModelDetailSection(title: title, value: value)
    }
}

private struct ModelDetailSummaryView: View {
    let summary: ModelDetailSummary

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.fields.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(summary.fields) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(field.value)
                                .font(.callout)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            ForEach(summary.sections.prefix(2)) { section in
                DisclosureGroup(section.title) {
                    ScrollView {
                        Text(section.value)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(6)
                    }
                    .frame(height: 120)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(8)
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        self?.trimmedNonEmpty
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var firstLine: String {
        components(separatedBy: .newlines).first ?? self
    }
}
