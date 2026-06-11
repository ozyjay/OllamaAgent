import SwiftUI

struct ModelDetailSummaryView: View {
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
