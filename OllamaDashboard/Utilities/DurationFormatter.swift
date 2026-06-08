import Foundation

enum DurationFormatter {
    static func nanoseconds(_ value: Int64?) -> String {
        guard let value else { return "Unknown" }
        let seconds = Double(value) / 1_000_000_000
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1_000)
        }
        return String(format: "%.2f s", seconds)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
