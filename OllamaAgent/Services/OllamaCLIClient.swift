@preconcurrency import Foundation

enum CLIError: LocalizedError, Equatable {
    case invalidModelName
    case executableNotFound
    case failed(Int32, String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidModelName: return "The model name contains unsupported characters."
        case .executableNotFound: return "The ollama CLI could not be found."
        case .failed(let code, let output): return "Command failed with exit code \(code): \(output)"
        case .timedOut: return "The command timed out."
        }
    }
}

protocol OllamaCLIClientProviding {
    func findOllamaBinary() async -> String?
    func stopModel(name: String) async throws
    func psRaw() async throws -> String
    func readLogs(maxLines: Int, maxBytes: UInt64) async throws -> String
}

enum OllamaLogTail {
    static let defaultMaxLines = 200
    static let defaultMaxBytes: UInt64 = 512 * 1_024

    static func tail(_ text: String, maxLines: Int) -> String {
        guard maxLines > 0 else { return "" }
        return text.split(separator: "\n").suffix(maxLines).joined(separator: "\n")
    }

    static func tail(_ data: Data, wasTruncated: Bool, maxLines: Int) -> String {
        var text = String(decoding: data, as: UTF8.self)
        if wasTruncated {
            guard let firstLineBreak = text.firstIndex(of: "\n") else { return "" }
            text = String(text[text.index(after: firstLineBreak)...])
        }
        return tail(text, maxLines: maxLines)
    }

    static func newestFirst(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .reversed()
            .joined(separator: "\n")
    }
}

enum OllamaLogCategory: String, CaseIterable, Identifiable {
    case errors = "Errors"
    case warnings = "Warnings"
    case requests = "Requests"
    case modelLoad = "Model Load"
    case lifecycle = "Lifecycle"

    var id: String { rawValue }
}

enum OllamaLogSeverity: String, Equatable {
    case error = "Error"
    case warning = "Warning"
    case request = "Request"
    case model = "Model"
    case lifecycle = "Service"
    case info = "Info"
}

struct OllamaLogEntry: Identifiable, Equatable {
    let id: Int
    let rawLine: String
    let summary: String
    let detail: String
    let categories: Set<OllamaLogCategory>
    let severity: OllamaLogSeverity
}

enum OllamaLogClassifier {
    static func categories(for line: String) -> Set<OllamaLogCategory> {
        let lowercased = line.lowercased()
        var categories: Set<OllamaLogCategory> = []

        if containsAny(lowercased, [
            " error", "error=", "level=error", "fatal", "panic", "exception",
            "failed", "failure", "out of memory", "oom", "runner exited",
            "segmentation", "signal: killed", "status=500", " 500 "
        ]) {
            categories.insert(.errors)
        }
        if containsAny(lowercased, [" warn", "warning", "level=warn", "status=4"]) {
            categories.insert(.warnings)
        }
        if containsAny(lowercased, [
            "/api/generate", "/api/chat", "/api/embed", "/v1/chat/completions",
            "method=post", "generate request", "chat request"
        ]) {
            categories.insert(.requests)
        }
        if containsAny(lowercased, [
            "loading model", "loaded model", "load model", "llm server",
            "runner", "model_path", "expires_at"
        ]) {
            categories.insert(.modelLoad)
        }
        if containsAny(lowercased, [
            "listening", "server started", "starting", "shutdown", "stopping",
            "unload", "keep_alive", "server config"
        ]) {
            categories.insert(.lifecycle)
        }

        return categories
    }

    static func filteredLines(
        in text: String,
        selectedCategories: Set<OllamaLogCategory>,
        searchText: String
    ) -> String {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let categoryMatches = selectedCategories.isEmpty
                    || !categories(for: line).isDisjoint(with: selectedCategories)
                let searchMatches = trimmedSearch.isEmpty
                    || line.localizedCaseInsensitiveContains(trimmedSearch)
                return categoryMatches && searchMatches
            }
            .joined(separator: "\n")
    }

    static func entries(
        in text: String,
        selectedCategories: Set<OllamaLogCategory>,
        searchText: String
    ) -> [OllamaLogEntry] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .enumerated()
            .compactMap { index, line in
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let categories = categories(for: line)
                let categoryMatches = selectedCategories.isEmpty || !categories.isDisjoint(with: selectedCategories)
                let searchMatches = trimmedSearch.isEmpty || line.localizedCaseInsensitiveContains(trimmedSearch)
                guard categoryMatches && searchMatches else { return nil }

                let severity = severity(for: categories)
                return OllamaLogEntry(
                    id: index,
                    rawLine: line,
                    summary: summary(for: line, severity: severity),
                    detail: line,
                    categories: categories,
                    severity: severity
                )
            }
    }

    private static func containsAny(_ line: String, _ needles: [String]) -> Bool {
        needles.contains { line.contains($0) }
    }

    private static func severity(for categories: Set<OllamaLogCategory>) -> OllamaLogSeverity {
        if categories.contains(.errors) { return .error }
        if categories.contains(.warnings) { return .warning }
        if categories.contains(.requests) { return .request }
        if categories.contains(.modelLoad) { return .model }
        if categories.contains(.lifecycle) { return .lifecycle }
        return .info
    }

    private static func summary(for line: String, severity: OllamaLogSeverity) -> String {
        let message = keyValue("msg", in: line) ?? strippedMetadata(from: line)
        switch severity {
        case .request:
            let path = keyValue("path", in: line)
                ?? firstKnownPath(in: line)
                ?? "request"
            let model = keyValue("model", in: line).map { " for \($0)" } ?? ""
            let status = keyValue("status", in: line).map { " returned \($0)" } ?? ""
            return "Request \(path)\(model)\(status)"
        case .model:
            let model = keyValue("model", in: line).map { " \($0)" } ?? ""
            return "Model\(model): \(message)"
        case .lifecycle:
            return "Service: \(message)"
        case .error:
            return "Error: \(message)"
        case .warning:
            return "Warning: \(message)"
        case .info:
            return message
        }
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

    private static func firstKnownPath(in line: String) -> String? {
        ["/api/generate", "/api/chat", "/api/embed", "/v1/chat/completions"].first { line.contains($0) }
    }

    private static func strippedMetadata(from line: String) -> String {
        var result = line
        for key in ["time", "level", "source"] {
            if let value = keyValue(key, in: result) {
                result = result.replacingOccurrences(of: "\(key)=\(value)", with: "")
                result = result.replacingOccurrences(of: "\(key)=\"\(value)\"", with: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class OllamaCLIClient: OllamaCLIClientProviding {
    var executableURL: URL

    init(executablePath: String = "/usr/local/bin/ollama") {
        executableURL = URL(fileURLWithPath: executablePath)
    }

    func findOllamaBinary() async -> String? {
        let candidates = [
            executableURL.path,
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama"
        ]
        if let direct = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return direct
        }
        return try? await run(URL(fileURLWithPath: "/usr/bin/which"), arguments: ["ollama"], timeout: 5)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stopModel(name: String) async throws {
        guard ModelNameValidator.isValid(name) else { throw CLIError.invalidModelName }
        guard let binary = await findOllamaBinary() else { throw CLIError.executableNotFound }
        _ = try await run(URL(fileURLWithPath: binary), arguments: ["stop", name], timeout: 15)
    }

    func psRaw() async throws -> String {
        guard let binary = await findOllamaBinary() else { throw CLIError.executableNotFound }
        return try await run(URL(fileURLWithPath: binary), arguments: ["ps"], timeout: 10)
    }

    func readLogs(
        maxLines: Int = OllamaLogTail.defaultMaxLines,
        maxBytes: UInt64 = OllamaLogTail.defaultMaxBytes
    ) async throws -> String {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/logs/server.log")
        let handle = try FileHandle(forReadingFrom: logURL)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        let startOffset = fileSize > maxBytes ? fileSize - maxBytes : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        return OllamaLogTail.tail(data, wasTruncated: startOffset > 0, maxLines: maxLines)
    }

    private func run(_ executable: URL, arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let gate = CLIContinuationGate()

            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                }
                gate.resume(continuation, with: .failure(CLIError.timedOut))
            }

            process.terminationHandler = { process in
                timer.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    gate.resume(continuation, with: .success(output))
                } else {
                    gate.resume(continuation, with: .failure(CLIError.failed(process.terminationStatus, output)))
                }
            }

            do {
                try process.run()
                timer.resume()
            } catch {
                timer.cancel()
                gate.resume(continuation, with: .failure(error))
            }
        }
    }
}

private final class CLIContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<String, Error>, with result: Result<String, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        continuation.resume(with: result)
    }
}
