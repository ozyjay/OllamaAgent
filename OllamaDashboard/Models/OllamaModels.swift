import Foundation

struct OllamaVersion: Codable, Equatable {
    let version: String
}

struct InstalledModelsResponse: Codable {
    let models: [InstalledModel]
}

struct InstalledModel: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let modifiedAt: Date?
    let size: Int64?
    let digest: String?
    let details: ModelDetails?

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
        case digest
        case details
    }
}

struct RunningModelsResponse: Codable {
    let models: [RunningModel]
}

struct RunningModel: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let model: String?
    let size: Int64?
    let digest: String?
    let details: ModelDetails?
    let expiresAt: Date?
    let sizeVRAM: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case model
        case size
        case digest
        case details
        case expiresAt = "expires_at"
        case sizeVRAM = "size_vram"
    }
}

struct ModelDetails: Codable, Equatable {
    let parentModel: String?
    let format: String?
    let family: String?
    let families: [String]?
    let parameterSize: String?
    let quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case parentModel = "parent_model"
        case format
        case family
        case families
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

struct ModelDetail: Codable, Equatable {
    let license: String?
    let modelfile: String?
    let parameters: String?
    let template: String?
    let details: ModelDetails?
    let modelInfo: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case license
        case modelfile
        case parameters
        case template
        case details
        case modelInfo = "model_info"
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct WarmModelResult: Equatable {
    let model: String
    let keepAlive: String
    let loaded: Bool
}

struct UnloadResult: Equatable {
    let model: String
    let method: String
    let unloaded: Bool
}

struct BenchmarkResult: Codable, Equatable {
    let model: String
    let prompt: String
    let response: String
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let promptEvalDuration: Int64?
    let evalCount: Int?
    let evalDuration: Int64?

    var outputTokensPerSecond: Double? {
        guard let evalCount, let evalDuration, evalDuration > 0 else { return nil }
        return Double(evalCount) / (Double(evalDuration) / 1_000_000_000)
    }

    var wasAlreadyWarm: Bool {
        guard let loadDuration else { return false }
        return loadDuration < 50_000_000
    }
}

struct GenerateResponseChunk: Codable, Equatable {
    let model: String?
    let response: String?
    let done: Bool?
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let promptEvalDuration: Int64?
    let evalCount: Int?
    let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case model
        case response
        case done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}
