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
