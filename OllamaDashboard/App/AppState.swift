import Foundation

enum DashboardTab: String, CaseIterable, Identifiable {
    case service = "Service"
    case installed = "Installed"
    case running = "Running"
    case context = "Context"
    case benchmark = "Benchmark"
    case profiles = "Profiles"
    case settings = "Settings"
    case advanced = "Advanced"

    var id: String { rawValue }
}
