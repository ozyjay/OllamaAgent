import Combine
@preconcurrency import Foundation

struct CPUUsage: Equatable {
    let userPercent: Double
    let systemPercent: Double
    let idlePercent: Double

    var busyPercent: Double {
        min(100, max(0, userPercent + systemPercent))
    }
}

struct GPUMemoryStatus: Equatable {
    let totalBytes: Int64?
    let availableBytes: Int64?
    let freeBytes: Int64?
    let peakBytes: Int64?
    let sampledAt: Date

    var usageFraction: Double? {
        if let peakBytes {
            let capacityBytes = totalBytes ?? availableBytes
            if let capacityBytes, capacityBytes > 0 {
                return clampedFraction(Double(peakBytes) / Double(capacityBytes))
            }
        }
        if let availableBytes, let freeBytes, availableBytes > 0 {
            let usedBytes = max(0, availableBytes - freeBytes)
            return clampedFraction(Double(usedBytes) / Double(availableBytes))
        }
        return nil
    }

    private func clampedFraction(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

struct SystemResourceSnapshot: Equatable {
    let cpuUsage: CPUUsage?
    let gpuStatus: GPUMemoryStatus?
    let sampledAt: Date

    static let empty = SystemResourceSnapshot(cpuUsage: nil, gpuStatus: nil, sampledAt: Date())
}

enum SystemResourceParser {
    static func cpuUsage(from text: String) -> CPUUsage? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains("CPU usage:") }) else {
            return nil
        }

        let segments = line
            .replacingOccurrences(of: "CPU usage:", with: "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        guard
            let user = percentValue(in: segments, label: "user"),
            let system = percentValue(in: segments, label: "sys"),
            let idle = percentValue(in: segments, label: "idle")
        else {
            return nil
        }

        return CPUUsage(userPercent: user, systemPercent: system, idlePercent: idle)
    }

    static func gpuStatus(from text: String, sampledAt: Date = Date()) -> GPUMemoryStatus? {
        var totalBytes: Int64?
        var availableBytes: Int64?
        var freeBytes: Int64?
        var peakBytes: Int64?

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let lowercased = line.lowercased()
            if lowercased.contains("inference compute") || lowercased.contains("updated vram") {
                totalBytes = keyValue("total", in: line).flatMap(byteCount) ?? totalBytes
            }
            if lowercased.contains("gpu memory") {
                totalBytes = keyValue("total", in: line).flatMap(byteCount) ?? totalBytes
                availableBytes = keyValue("available", in: line).flatMap(byteCount)
                freeBytes = keyValue("free", in: line).flatMap(byteCount)
            }
            if lowercased.contains("peak memory") {
                peakBytes = keyValue("peak memory", in: line).flatMap(byteCount)
                    ?? keyValue("size", in: line).flatMap(byteCount)
                    ?? peakBytes
            }
        }

        guard totalBytes != nil || availableBytes != nil || freeBytes != nil || peakBytes != nil else { return nil }
        return GPUMemoryStatus(
            totalBytes: totalBytes,
            availableBytes: availableBytes,
            freeBytes: freeBytes,
            peakBytes: peakBytes,
            sampledAt: sampledAt
        )
    }

    static func byteCount(from value: String) -> Int64? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard let numberPart = parts.first, let number = Double(numberPart) else { return nil }
        let unit = parts.dropFirst().first.map { String($0).lowercased() } ?? "b"
        let multiplier: Double
        switch unit {
        case "b", "byte", "bytes":
            multiplier = 1
        case "kib", "kb":
            multiplier = 1_024
        case "mib", "mb":
            multiplier = 1_024 * 1_024
        case "gib", "gb":
            multiplier = 1_024 * 1_024 * 1_024
        case "tib", "tb":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024
        default:
            return nil
        }
        return Int64((number * multiplier).rounded())
    }

    private static func percentValue(in segments: [String], label: String) -> Double? {
        guard let segment = segments.first(where: { $0.contains(label) }) else { return nil }
        let numberText = segment.split(separator: "%").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return numberText.flatMap(Double.init)
    }

    private static func keyValue(_ key: String, in line: String) -> String? {
        guard let keyRange = line.range(of: "\(key)=") else { return nil }
        var start = keyRange.upperBound
        if start < line.endIndex, line[start] == "\"" {
            start = line.index(after: start)
            guard let end = line[start...].firstIndex(of: "\"") else { return nil }
            return String(line[start..<end])
        }

        let end = line[start...].firstIndex(where: { $0 == " " || $0 == "\t" }) ?? line.endIndex
        let value = String(line[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

@MainActor
final class SystemResourceMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemResourceSnapshot.empty

    private static let resourceLogMaxLines = 2_000
    private static let resourceLogMaxBytes: UInt64 = 2 * 1_024 * 1_024

    private var refreshTask: Task<Void, Never>?

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        async let cpuOutput = Self.topOutput()
        async let logText = Self.ollamaLogText()
        let sampledAt = Date()
        snapshot = SystemResourceSnapshot(
            cpuUsage: await cpuOutput.flatMap(SystemResourceParser.cpuUsage),
            gpuStatus: await SystemResourceParser.gpuStatus(from: logText ?? "", sampledAt: sampledAt),
            sampledAt: sampledAt
        )
    }

    nonisolated private static func topOutput() async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
            process.arguments = ["-l", "1", "-n", "0", "-s", "0"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            } catch {
                return nil
            }
        }.value
    }

    nonisolated private static func ollamaLogText() async -> String? {
        await Task.detached(priority: .utility) {
            try? await OllamaCLIClient().readLogs(
                maxLines: resourceLogMaxLines,
                maxBytes: resourceLogMaxBytes
            )
        }.value
    }
}
