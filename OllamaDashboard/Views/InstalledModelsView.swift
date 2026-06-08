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
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Picker("Sort", selection: $sort) {
                    ForEach(InstalledModelSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 130)
                Button("Refresh") { Task { await monitor.refreshAll() } }
            }
            if filteredModels.isEmpty {
                EmptyStateView(title: "No installed models", detail: "Install models with Ollama, then refresh.")
            } else {
                Table(filteredModels, selection: $selectedModelID) {
                    TableColumn("Name") { Text($0.name).textSelection(.enabled) }
                    TableColumn("Size") { Text(ByteFormatter.string(from: $0.size)) }
                    TableColumn("Modified") { Text(DurationFormatter.date($0.modifiedAt)) }
                    TableColumn("Digest") { Text($0.digest ?? "Unknown").lineLimit(1).textSelection(.enabled) }
                }
                HStack {
                    Button("Show Details") {
                        Task { await loadDetail() }
                    }
                    .disabled(selectedModel == nil)
                    Spacer()
                }
                if let detailSummary {
                    ModelDetailSummaryView(summary: detailSummary)
                }
                if !detailError.isEmpty {
                    Text(detailError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: selectedModelID) { _ in
            detailSummary = nil
            detailError = ""
        }
    }

    private func loadDetail() async {
        guard let selectedModel else { return }
        do {
            let detail = try await OllamaAPIClient(baseURL: settings.baseURL).showModel(name: selectedModel.name)
            detailSummary = ModelDetailSummary(detail: detail)
            detailError = ""
        } catch {
            detailSummary = nil
            detailError = error.localizedDescription
        }
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
        fields = [
            Self.field("Format", detail.details?.format),
            Self.field("Family", detail.details?.family ?? detail.details?.families?.joined(separator: ", ")),
            Self.field("Parameters", detail.details?.parameterSize),
            Self.field("Quantization", detail.details?.quantizationLevel),
            Self.field("License", detail.license?.firstLine)
        ].compactMap(\.self)

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
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 72)
                }
            }
        }
        .padding(.top, 2)
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
