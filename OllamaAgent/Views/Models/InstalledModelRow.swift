import SwiftUI

struct InstalledModelRow: View {
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
                        .foregroundStyle(status == .cold ? (isSelected ? .white.opacity(0.9) : .secondary) : (isSelected ? .white : .green))
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
