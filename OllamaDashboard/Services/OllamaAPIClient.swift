import Foundation

enum OllamaAPIError: LocalizedError, Equatable {
    case invalidBaseURL
    case badStatus(Int)
    case emptyResponse
    case invalidModelName

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "The Ollama base URL is not valid."
        case .badStatus(let code): return "Ollama returned HTTP \(code)."
        case .emptyResponse: return "Ollama returned an empty response."
        case .invalidModelName: return "The model name contains unsupported characters."
        }
    }
}

final class OllamaAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
    }

    func getVersion() async throws -> OllamaVersion {
        try await get("api/version")
    }

    func getInstalledModels() async throws -> [InstalledModel] {
        let response: InstalledModelsResponse = try await get("api/tags")
        return response.models
    }

    func getRunningModels() async throws -> [RunningModel] {
        let response: RunningModelsResponse = try await get("api/ps")
        return response.models
    }

    func showModel(name: String) async throws -> ModelDetail {
        guard ModelNameValidator.isValid(name) else { throw OllamaAPIError.invalidModelName }
        return try await post("api/show", body: ["model": name])
    }

    func warmModel(name: String, keepAlive: String, numCtx: Int?, options: [String: JSONValue] = [:]) async throws -> WarmModelResult {
        guard ModelNameValidator.isValid(name) else { throw OllamaAPIError.invalidModelName }
        var body: [String: JSONValue] = [
            "model": .string(name),
            "prompt": .string(""),
            "stream": .bool(false),
            "keep_alive": .string(keepAlive)
        ]
        var requestOptions = options
        requestOptions.removeValue(forKey: "num_predict")
        if let numCtx, requestOptions["num_ctx"] == nil {
            requestOptions["num_ctx"] = .number(Double(numCtx))
        }
        if !requestOptions.isEmpty {
            body["options"] = .object(requestOptions)
        }
        let _: GenerateResponseChunk = try await post("api/generate", body: body)
        return WarmModelResult(model: name, keepAlive: keepAlive, loaded: true)
    }

    func unloadModelViaAPI(name: String) async throws -> UnloadResult {
        guard ModelNameValidator.isValid(name) else { throw OllamaAPIError.invalidModelName }
        let body: [String: JSONValue] = [
            "model": .string(name),
            "prompt": .string(""),
            "stream": .bool(false),
            "keep_alive": .string("0")
        ]
        let _: GenerateResponseChunk = try await post("api/generate", body: body)
        return UnloadResult(model: name, method: "API keep_alive=0", unloaded: true)
    }

    func runBenchmark(
        model: String,
        prompt: String,
        numCtx: Int?,
        keepAlive: String,
        options: [String: JSONValue] = [:]
    ) async throws -> BenchmarkResult {
        guard ModelNameValidator.isValid(model) else { throw OllamaAPIError.invalidModelName }
        var body: [String: JSONValue] = [
            "model": .string(model),
            "prompt": .string(prompt),
            "stream": .bool(false),
            "keep_alive": .string(keepAlive)
        ]
        var requestOptions = options
        if let numCtx, requestOptions["num_ctx"] == nil {
            requestOptions["num_ctx"] = .number(Double(numCtx))
        }
        if !requestOptions.isEmpty {
            body["options"] = .object(requestOptions)
        }
        let chunk: GenerateResponseChunk = try await post("api/generate", body: body)
        return BenchmarkResult(
            model: model,
            prompt: prompt,
            response: chunk.response ?? "",
            totalDuration: chunk.totalDuration,
            loadDuration: chunk.loadDuration,
            promptEvalCount: chunk.promptEvalCount,
            promptEvalDuration: chunk.promptEvalDuration,
            evalCount: chunk.evalCount,
            evalDuration: chunk.evalDuration
        )
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: try url(for: path), timeoutInterval: 8)
        request.httpMethod = "GET"
        return try await send(request)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: try url(for: path), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaAPIError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw OllamaAPIError.emptyResponse }
        return try decoder.decode(T.self, from: data)
    }

    private func url(for path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw OllamaAPIError.invalidBaseURL
        }
        return url
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
        }
    }
}
