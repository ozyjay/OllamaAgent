import Foundation
import os

enum AgentLogger {
    static let app = Logger(subsystem: "OllamaAgent", category: "App")
    static let network = Logger(subsystem: "OllamaAgent", category: "Network")
}
