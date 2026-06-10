import Foundation

enum DashboardTab: String, CaseIterable, Identifiable {
    case logs = "Logs"
    case profiles = "Profiles"
    case models = "Models"
    case settings = "Settings"

    var id: String { rawValue }
}
