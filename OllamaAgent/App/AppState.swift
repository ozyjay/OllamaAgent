import Combine
import Foundation

enum AgentSection: String, CaseIterable, Identifiable {
    case logs = "Logs"
    case profiles = "Profiles"
    case models = "Models"
    case settings = "Settings"

    var id: String { rawValue }

    var navigationTitle: String { rawValue }

    var menuTitle: String { rawValue }

    var systemImage: String {
        switch self {
        case .logs: return "doc.text.magnifyingglass"
        case .profiles: return "slider.horizontal.3"
        case .models: return "shippingbox"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AgentNavigation: ObservableObject {
    @Published var selectedTab: AgentSection = .logs
}

enum StatusMenuDestination: CaseIterable, Identifiable {
    case logs
    case models
    case settings

    var id: AgentSection { tab }

    var title: String { tab.menuTitle }

    var tab: AgentSection {
        switch self {
        case .logs: return .logs
        case .models: return .models
        case .settings: return .settings
        }
    }
}
