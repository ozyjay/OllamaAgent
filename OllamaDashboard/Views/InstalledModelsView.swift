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
    @State private var detailText = ""

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Installed Models").font(.title3.bold())
                Spacer()
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Picker("Sort", selection: $sort) {
                    ForEach(InstalledModelSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 150)
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
                if !detailText.isEmpty {
                    ScrollView {
                        Text(detailText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 90)
                }
            }
        }
    }

    private func loadDetail() async {
        guard let selectedModel else { return }
        do {
            let detail = try await OllamaAPIClient(baseURL: settings.baseURL).showModel(name: selectedModel.name)
            let data = try JSONEncoder.prettyPrinted.encode(detail)
            detailText = String(data: data, encoding: .utf8) ?? "Details loaded."
        } catch {
            detailText = error.localizedDescription
        }
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
