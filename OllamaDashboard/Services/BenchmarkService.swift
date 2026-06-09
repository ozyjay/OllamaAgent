import Foundation

enum BenchmarkPrompt: String, CaseIterable, Identifiable {
    case tiny
    case coding
    case reasoning
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tiny: return "Tiny"
        case .coding: return "Coding"
        case .reasoning: return "Reasoning"
        case .custom: return "Custom"
        }
    }

    var prompt: String {
        switch self {
        case .tiny: return "Reply with one sentence."
        case .coding: return "Write a small Swift function that reverses a string."
        case .reasoning: return "Explain the trade-off between short and long context windows."
        case .custom: return ""
        }
    }
}

struct BenchmarkService {
    let client: OllamaAPIClient

    func run(
        model: String,
        preset: BenchmarkPrompt,
        customPrompt: String,
        numCtx: Int?,
        keepAlive: String,
        options: [String: JSONValue] = [:]
    ) async throws -> BenchmarkResult {
        let prompt = preset == .custom ? customPrompt : preset.prompt
        return try await client.runBenchmark(model: model, prompt: prompt, numCtx: numCtx, keepAlive: keepAlive, options: options)
    }
}
