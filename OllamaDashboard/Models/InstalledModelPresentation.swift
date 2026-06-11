import AppKit
import Foundation

struct ModelProfileUsage: Equatable {
    private var namesByModel: [String: String] = [:]

    mutating func record(profile: RuntimeProfile?, fallbackModel: String) {
        namesByModel[fallbackModel] = profile?.name ?? "No profile"
    }

    func profileName(for model: String) -> String? {
        namesByModel[model]
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
