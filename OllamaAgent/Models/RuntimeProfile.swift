import Foundation

enum ProfileContextPolicy: String, Codable, CaseIterable, Identifiable, Equatable {
    case modelDefault
    case lowRAM
    case balanced
    case maxKnown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .modelDefault: return "Model default"
        case .lowRAM: return "Low RAM"
        case .balanced: return "Balanced"
        case .maxKnown: return "Max known"
        }
    }

    func resolve(modelMaxContext: Int?) -> Int? {
        switch self {
        case .modelDefault:
            return nil
        case .lowRAM:
            return min(modelMaxContext ?? 4096, 4096)
        case .balanced:
            guard let modelMaxContext else { return nil }
            return min(modelMaxContext, 32_768)
        case .maxKnown:
            return modelMaxContext
        }
    }

    static func legacyPolicy(for numCtx: Int) -> ProfileContextPolicy {
        if numCtx <= 8192 { return .lowRAM }
        if numCtx <= 32_768 { return .balanced }
        return .maxKnown
    }
}

struct ModelContextOverride: Codable, Identifiable, Equatable {
    var id: UUID
    var model: String
    var numCtx: Int

    init(id: UUID = UUID(), model: String, numCtx: Int) {
        self.id = id
        self.model = model
        self.numCtx = numCtx
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case numCtx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        model = try container.decode(String.self, forKey: .model)
        numCtx = try container.decode(Int.self, forKey: .numCtx)
    }
}

struct ProfileGenerationOptions: Codable, Equatable {
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var repeatPenalty: Double?
    var repeatLastN: Int?
    var seed: Int?
    var mirostat: Int?
    var mirostatTau: Double?
    var mirostatEta: Double?
    var numPredict: Int?

    init(
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        repeatPenalty: Double? = nil,
        repeatLastN: Int? = nil,
        seed: Int? = nil,
        mirostat: Int? = nil,
        mirostatTau: Double? = nil,
        mirostatEta: Double? = nil,
        numPredict: Int? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.seed = seed
        self.mirostat = mirostat
        self.mirostatTau = mirostatTau
        self.mirostatEta = mirostatEta
        self.numPredict = numPredict
    }

    init(modelParameters: String?) {
        self.init()
        for line in modelParameters?.split(whereSeparator: \.isNewline) ?? [] {
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "temperature":
                temperature = Double(value)
            case "top_p":
                topP = Double(value)
            case "top_k":
                topK = Int(value)
            case "repeat_penalty":
                repeatPenalty = Double(value)
            case "repeat_last_n":
                repeatLastN = Int(value)
            case "seed":
                seed = Int(value)
            case "mirostat":
                mirostat = Int(value)
            case "mirostat_tau":
                mirostatTau = Double(value)
            case "mirostat_eta":
                mirostatEta = Double(value)
            case "num_predict":
                numPredict = Int(value)
            default:
                continue
            }
        }
    }

    var isEmpty: Bool {
        requestOptions().isEmpty
    }

    func requestOptions() -> [String: JSONValue] {
        var options: [String: JSONValue] = [:]
        if let temperature { options["temperature"] = .number(temperature) }
        if let topP { options["top_p"] = .number(topP) }
        if let topK { options["top_k"] = .number(Double(topK)) }
        if let repeatPenalty { options["repeat_penalty"] = .number(repeatPenalty) }
        if let repeatLastN { options["repeat_last_n"] = .number(Double(repeatLastN)) }
        if let seed { options["seed"] = .number(Double(seed)) }
        if let mirostat { options["mirostat"] = .number(Double(mirostat)) }
        if let mirostatTau { options["mirostat_tau"] = .number(mirostatTau) }
        if let mirostatEta { options["mirostat_eta"] = .number(mirostatEta) }
        if let numPredict { options["num_predict"] = .number(Double(numPredict)) }
        return options
    }

    func valueRows() -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let temperature { rows.append(("Temperature", Self.format(temperature))) }
        if let topP { rows.append(("Top P", Self.format(topP))) }
        if let topK { rows.append(("Top K", String(topK))) }
        if let repeatPenalty { rows.append(("Repeat penalty", Self.format(repeatPenalty))) }
        if let repeatLastN { rows.append(("Repeat last N", String(repeatLastN))) }
        if let seed { rows.append(("Seed", String(seed))) }
        if let mirostat { rows.append(("Mirostat", String(mirostat))) }
        if let mirostatTau { rows.append(("Mirostat tau", Self.format(mirostatTau))) }
        if let mirostatEta { rows.append(("Mirostat eta", Self.format(mirostatEta))) }
        if let numPredict { rows.append(("Prediction limit", String(numPredict))) }
        return rows
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3g", value)
    }
}

struct RuntimeProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var preferredModel: String
    var contextPolicy: ProfileContextPolicy
    var contextOverrides: [ModelContextOverride]
    var keepAlive: String
    var numPredict: Int
    var temperature: Double
    var generationOptions: ProfileGenerationOptions
    var notes: String
    var purpose: String

    func resolvedModel(currentModel: String) -> String {
        let preferredModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return preferredModel.isEmpty ? currentModel : preferredModel
    }

    init(
        id: UUID,
        name: String,
        preferredModel: String,
        contextPolicy: ProfileContextPolicy,
        contextOverrides: [ModelContextOverride],
        keepAlive: String,
        numPredict: Int,
        temperature: Double,
        generationOptions: ProfileGenerationOptions = ProfileGenerationOptions(),
        notes: String,
        purpose: String
    ) {
        self.id = id
        self.name = name
        self.preferredModel = preferredModel
        self.contextPolicy = contextPolicy
        self.contextOverrides = contextOverrides
        self.keepAlive = keepAlive
        self.numPredict = numPredict
        self.temperature = temperature
        self.generationOptions = generationOptions
        self.notes = notes
        self.purpose = purpose
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case preferredModel
        case numCtx
        case contextPolicy
        case contextOverrides
        case keepAlive
        case numPredict
        case temperature
        case generationOptions
        case notes
        case purpose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        preferredModel = try container.decode(String.self, forKey: .preferredModel)
        keepAlive = try container.decode(String.self, forKey: .keepAlive)
        numPredict = try container.decode(Int.self, forKey: .numPredict)
        temperature = try container.decode(Double.self, forKey: .temperature)
        generationOptions = try container.decodeIfPresent(ProfileGenerationOptions.self, forKey: .generationOptions)
            ?? ProfileGenerationOptions(temperature: temperature, numPredict: numPredict)
        notes = try container.decode(String.self, forKey: .notes)
        purpose = try container.decode(String.self, forKey: .purpose)

        if let contextPolicy = try container.decodeIfPresent(ProfileContextPolicy.self, forKey: .contextPolicy) {
            self.contextPolicy = contextPolicy
        } else if let legacyNumCtx = try container.decodeIfPresent(Int.self, forKey: .numCtx) {
            contextPolicy = ProfileContextPolicy.legacyPolicy(for: legacyNumCtx)
        } else {
            contextPolicy = .modelDefault
        }
        contextOverrides = try container.decodeIfPresent([ModelContextOverride].self, forKey: .contextOverrides) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(preferredModel, forKey: .preferredModel)
        try container.encode(contextPolicy, forKey: .contextPolicy)
        try container.encode(contextOverrides, forKey: .contextOverrides)
        try container.encode(keepAlive, forKey: .keepAlive)
        try container.encode(numPredict, forKey: .numPredict)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(generationOptions, forKey: .generationOptions)
        try container.encode(notes, forKey: .notes)
        try container.encode(purpose, forKey: .purpose)
    }

    static let builtIns: [RuntimeProfile] = [
        RuntimeProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Coding - Conservative",
            preferredModel: "",
            contextPolicy: .balanced,
            contextOverrides: [],
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.1,
            generationOptions: ProfileGenerationOptions(temperature: 0.1, numPredict: 4096),
            notes: "Max loaded models is an app-side note only.",
            purpose: "Stable coding assistant"
        ),
        RuntimeProfile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Long Context",
            preferredModel: "",
            contextPolicy: .maxKnown,
            contextOverrides: [],
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.2,
            generationOptions: ProfileGenerationOptions(temperature: 0.2, numPredict: 4096),
            notes: "",
            purpose: "Larger project/document context"
        ),
        RuntimeProfile(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Low RAM",
            preferredModel: "",
            contextPolicy: .lowRAM,
            contextOverrides: [],
            keepAlive: "5m",
            numPredict: 2048,
            temperature: 0.2,
            generationOptions: ProfileGenerationOptions(temperature: 0.2, numPredict: 2048),
            notes: "",
            purpose: "Avoid keeping large models hot"
        )
    ]
}

struct AppliedRuntimeProfile: Equatable {
    let model: String
    let numCtx: Int?
    let keepAlive: String
    let contextStatus: String
    let options: [String: JSONValue]

    init(profile: RuntimeProfile, currentModel: String, modelMaxContext: Int? = nil) {
        let resolvedModel = profile.resolvedModel(currentModel: currentModel)
        let resolvedNumCtx: Int?
        let resolvedContextStatus: String

        if let override = profile.contextOverrides.first(where: { $0.model == resolvedModel }) {
            if let modelMaxContext, override.numCtx > modelMaxContext {
                resolvedNumCtx = modelMaxContext
                resolvedContextStatus = "num_ctx \(modelMaxContext) from per-model override, clamped to model maximum."
            } else {
                resolvedNumCtx = override.numCtx
                resolvedContextStatus = "num_ctx \(override.numCtx) from per-model override."
            }
        } else {
            resolvedNumCtx = profile.contextPolicy.resolve(modelMaxContext: modelMaxContext)
            if let resolvedNumCtx {
                resolvedContextStatus = "num_ctx \(resolvedNumCtx) from \(profile.contextPolicy.label.lowercased()) policy."
            } else {
                resolvedContextStatus = "Using Ollama model default context."
            }
        }

        model = resolvedModel
        numCtx = resolvedNumCtx
        keepAlive = profile.keepAlive
        contextStatus = resolvedContextStatus
        var resolvedOptions = profile.generationOptions.requestOptions()
        if resolvedOptions["temperature"] == nil {
            resolvedOptions["temperature"] = .number(profile.temperature)
        }
        if resolvedOptions["num_predict"] == nil {
            resolvedOptions["num_predict"] = .number(Double(profile.numPredict))
        }
        if let resolvedNumCtx {
            resolvedOptions["num_ctx"] = .number(Double(resolvedNumCtx))
        }
        options = resolvedOptions
    }
}
