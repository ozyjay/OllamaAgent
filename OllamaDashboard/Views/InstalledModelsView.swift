import SwiftUI

enum InstalledModelSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case size = "Size"
    case modified = "Modified"
    var id: String { rawValue }
}

struct InstalledModelsView: View {
    @ObservedObject var monitor: OllamaServiceMonitor
    @EnvironmentObject private var settings: AppSettings
    @State private var searchText = ""
    @State private var sort: InstalledModelSort = .name
    @State private var selectedModelID: InstalledModel.ID?
    @State private var detailModelID: InstalledModel.ID?
    @State private var detailSummary: ModelDetailSummary?
    @State private var detailError = ""

    var filteredModels: [InstalledModel] {
        let filtered = monitor.installedModels.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        switch sort {
        case .name: return filtered.sorted { $0.name < $1.name }
        case .size: return filtered.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .modified: return filtered.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
        }
    }

    var selectedModel: InstalledModel? {
        guard let selectedModelID else { return nil }
        return monitor.installedModels.first { $0.id == selectedModelID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Installed Models").font(.title3.bold())
                Spacer()
                Button("Refresh") { Task { await monitor.refreshAll() } }
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
            if filteredModels.isEmpty {
                EmptyStateView(title: "No installed models", detail: "Install models with Ollama, then refresh.")
            } else {
                List(selection: $selectedModelID) {
                    ForEach(filteredModels) { model in
                        InstalledModelRow(model: model)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                Task { await toggleDetail(for: model) }
                            }
                            .tag(model.id)
                    }
                }
                .listStyle(.inset)
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
    private var summary: InstalledModelRowSummary {
        InstalledModelRowSummary(model: model)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(summary.metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.trailingPrimary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if let trailingSecondary = summary.trailingSecondary {
                    Text(trailingSecondary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
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
