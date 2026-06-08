import Foundation
import os

enum DashboardLogger {
    static let app = Logger(subsystem: "OllamaDashboard", category: "App")
    static let network = Logger(subsystem: "OllamaDashboard", category: "Network")
}
