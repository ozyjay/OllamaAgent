import Foundation
import XCTest
@testable import OllamaDashboard

final class StubHTTPSession: HTTPSessionProviding, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let data: Data
        let error: (any Error)?

        init(statusCode: Int = 200, data: Data = Data(), error: Error? = nil) {
            self.statusCode = statusCode
            self.data = data
            self.error = error
        }
    }

    private actor Store {
        var stubs: [String: Stub] = [:]
        var requests: [URLRequest] = []

        func setStub(_ stub: Stub, for path: String) {
            stubs[path] = stub
        }

        func stub(for request: URLRequest) -> Stub {
            requests.append(request)
            let path = request.url?.path ?? ""
            return stubs[path] ?? Stub(statusCode: 404, data: Data())
        }

        func capturedRequests() -> [URLRequest] {
            requests
        }
    }

    private let store = Store()

    func setStub(_ stub: Stub, for path: String) async {
        await store.setStub(stub, for: path)
    }

    func capturedRequests() async -> [URLRequest] {
        await store.capturedRequests()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let stub = await store.stub(for: request)
        if let error = stub.error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (stub.data, response)
    }
}

struct StubAPIClient: OllamaAPIClientProviding {
    var versionResult: Result<OllamaVersion, Error> = .success(OllamaVersion(version: "0.0.0"))
    var installedResult: Result<[InstalledModel], Error> = .success([])
    var runningResult: Result<[RunningModel], Error> = .success([])
    var warmResult: Result<WarmModelResult, Error> = .success(WarmModelResult(model: "model", keepAlive: "30m", loaded: true))
    var unloadResult: Result<UnloadResult, Error> = .success(UnloadResult(model: "model", method: "API keep_alive=0", unloaded: true))
    var benchmarkResult: Result<BenchmarkResult, Error> = .success(
        BenchmarkResult(
            model: "model",
            prompt: "prompt",
            response: "ok",
            totalDuration: nil,
            loadDuration: nil,
            promptEvalCount: nil,
            promptEvalDuration: nil,
            evalCount: nil,
            evalDuration: nil
        )
    )
    var showResult: Result<ModelDetail, Error> = .success(
        ModelDetail(license: nil, modelfile: nil, parameters: nil, template: nil, details: nil, modelInfo: nil)
    )

    let onWarm: ((String, String, Int?, [String: JSONValue]) -> Void)?
    let onUnload: ((String) -> Void)?

    init(
        versionResult: Result<OllamaVersion, Error> = .success(OllamaVersion(version: "0.0.0")),
        installedResult: Result<[InstalledModel], Error> = .success([]),
        runningResult: Result<[RunningModel], Error> = .success([]),
        warmResult: Result<WarmModelResult, Error> = .success(WarmModelResult(model: "model", keepAlive: "30m", loaded: true)),
        unloadResult: Result<UnloadResult, Error> = .success(UnloadResult(model: "model", method: "API keep_alive=0", unloaded: true)),
        onWarm: ((String, String, Int?, [String: JSONValue]) -> Void)? = nil,
        onUnload: ((String) -> Void)? = nil
    ) {
        self.versionResult = versionResult
        self.installedResult = installedResult
        self.runningResult = runningResult
        self.warmResult = warmResult
        self.unloadResult = unloadResult
        self.onWarm = onWarm
        self.onUnload = onUnload
    }

    func getVersion() async throws -> OllamaVersion {
        try versionResult.get()
    }

    func getInstalledModels() async throws -> [InstalledModel] {
        try installedResult.get()
    }

    func getRunningModels() async throws -> [RunningModel] {
        try runningResult.get()
    }

    func showModel(name: String) async throws -> ModelDetail {
        try showResult.get()
    }

    func warmModel(name: String, keepAlive: String, numCtx: Int?, options: [String: JSONValue]) async throws -> WarmModelResult {
        onWarm?(name, keepAlive, numCtx, options)
        return try warmResult.get()
    }

    func unloadModelViaAPI(name: String) async throws -> UnloadResult {
        onUnload?(name)
        return try unloadResult.get()
    }

    func runBenchmark(
        model: String,
        prompt: String,
        numCtx: Int?,
        keepAlive: String,
        options: [String: JSONValue]
    ) async throws -> BenchmarkResult {
        try benchmarkResult.get()
    }
}

final class StubCLIClient: OllamaCLIClientProviding, @unchecked Sendable {
    var stopResult: Result<Void, Error> = .success(())
    private(set) var stoppedModels: [String] = []

    func findOllamaBinary() async -> String? {
        "/usr/local/bin/ollama"
    }

    func stopModel(name: String) async throws {
        stoppedModels.append(name)
        try stopResult.get()
    }

    func psRaw() async throws -> String {
        ""
    }

    func readLogs(maxLines: Int, maxBytes: UInt64) async throws -> String {
        ""
    }
}

struct TestError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}

func makeInstalledModel(
    name: String,
    modifiedAt: Date? = nil,
    size: Int64? = nil,
    digest: String? = nil,
    details: ModelDetails? = nil
) -> InstalledModel {
    InstalledModel(name: name, modifiedAt: modifiedAt, size: size, digest: digest, details: details)
}

func makeRunningModel(name: String, expiresAt: Date? = nil) -> RunningModel {
    RunningModel(
        name: name,
        model: nil,
        size: nil,
        digest: nil,
        details: nil,
        expiresAt: expiresAt,
        sizeVRAM: nil,
        contextLength: nil
    )
}
