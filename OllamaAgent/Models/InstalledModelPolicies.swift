import Foundation

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
    static func runningModel(
        for model: InstalledModel,
        runningModels: [RunningModel],
        now: Date = Date()
    ) -> RunningModel? {
        runningModels.first {
            isCurrent($0, now: now) && (namesMatch($0.name, model.name) || namesMatch($0.model, model.name))
        }
    }

    static func isActive(
        model: InstalledModel,
        runningModels: [RunningModel],
        activeModelNames: Set<String>,
        now: Date = Date()
    ) -> Bool {
        activeModelNames.contains { activeName in
            namesMatch(activeName, model.name)
                || runningModel(for: model, runningModels: runningModels, now: now).map {
                    namesMatch(activeName, $0.name) || namesMatch(activeName, $0.model)
                } == true
        }
    }

    static func status(
        for model: InstalledModel,
        runningModels: [RunningModel],
        activeModelNames: Set<String> = [],
        now: Date = Date()
    ) -> ModelLoadStatus {
        if isActive(model: model, runningModels: runningModels, activeModelNames: activeModelNames, now: now) {
            return .busy
        }
        return runningModel(for: model, runningModels: runningModels, now: now) == nil ? .idle : .warm
    }

    static func timeRemaining(for runningModel: RunningModel?, now: Date = Date()) -> String? {
        guard let expiresAt = runningModel?.expiresAt, expiresAt > now else { return nil }
        return WarmTimeRemainingFormatter.string(from: expiresAt.timeIntervalSince(now))
    }

    static func statusRows(
        installedModels: [InstalledModel],
        runningModels: [RunningModel],
        activeModelNames: Set<String> = [],
        now: Date = Date()
    ) -> [ModelStatusRow] {
        installedModels.map { model in
            let runningModel = runningModel(for: model, runningModels: runningModels, now: now)
            return ModelStatusRow(
                modelName: model.name,
                status: isActive(model: model, runningModels: runningModels, activeModelNames: activeModelNames, now: now)
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

    private static func isCurrent(_ runningModel: RunningModel, now: Date) -> Bool {
        guard let expiresAt = runningModel.expiresAt else { return true }
        return expiresAt > now
    }
}

enum InstalledModelActionPolicy {
    static func canWarmSelected(status: ModelLoadStatus?, isWarming: Bool, isUnloading: Bool = false) -> Bool {
        status == .idle && !isWarming && !isUnloading
    }

    static func canUnloadSelected(isWarm: Bool, isWarming: Bool, isUnloading: Bool) -> Bool {
        isWarm && !isWarming && !isUnloading
    }

    static func canUseSelectionActions(hasSelection: Bool, isWarming: Bool, isUnloading: Bool) -> Bool {
        hasSelection && !isWarming && !isUnloading
    }
}

enum ModelLifecycleTransitionPolicy {
    static func installedModelStatus(
        modelName: String,
        installedModels: [InstalledModel],
        runningModels: [RunningModel],
        activeModelNames: Set<String>,
        now: Date
    ) -> ModelLoadStatus? {
        guard let model = installedModels.first(where: { $0.name == modelName }) else { return nil }
        return ModelStatusPolicy.status(
            for: model,
            runningModels: runningModels,
            activeModelNames: activeModelNames,
            now: now
        )
    }

    static func installedModelReached(
        modelName: String,
        targetStatus: ModelLoadStatus,
        installedModels: [InstalledModel],
        runningModels: [RunningModel],
        activeModelNames: Set<String>,
        now: Date
    ) -> Bool {
        installedModelStatus(
            modelName: modelName,
            installedModels: installedModels,
            runningModels: runningModels,
            activeModelNames: activeModelNames,
            now: now
        ) == targetStatus
    }

    static func runningModelIsAbsent(modelName: String, runningModels: [RunningModel], now: Date) -> Bool {
        runningModels.allSatisfy { runningModel in
            guard namesMatch(runningModel.name, modelName) else { return true }
            guard let expiresAt = runningModel.expiresAt else { return false }
            return expiresAt <= now
        }
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedName(lhs) == normalizedName(rhs)
    }

    private static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(":latest") ? String(trimmed.dropLast(":latest".count)) : trimmed
    }
}

enum PreferredModelSelectionPolicy {
    static func selectedInstalledModelID(for profile: RuntimeProfile?, installedModels: [InstalledModel]) -> InstalledModel.ID? {
        guard let preferredModel = profile?.preferredModel.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferredModel.isEmpty
        else {
            return nil
        }
        return installedModels.first { namesMatch($0.name, preferredModel) }?.id
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedName(lhs) == normalizedName(rhs)
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
