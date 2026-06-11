import Foundation

struct ModelWarmRequest: Equatable {
    let model: String
    let keepAlive: String
    let numCtx: Int?
    let options: [String: JSONValue]
    let statusDetail: String

    static func resolve(
        selectedModelName: String,
        profile: RuntimeProfile?,
        modelMaxContext: Int?,
        defaultKeepAlive: String = "30m"
    ) -> ModelWarmRequest {
        guard let profile else {
            return ModelWarmRequest(
                model: selectedModelName,
                keepAlive: defaultKeepAlive,
                numCtx: nil,
                options: [:],
                statusDetail: "keep_alive \(defaultKeepAlive), model default context."
            )
        }

        let selectedModelProfile = RuntimeProfile(
            id: profile.id,
            name: profile.name,
            preferredModel: "",
            contextPolicy: profile.contextPolicy,
            contextOverrides: profile.contextOverrides,
            keepAlive: profile.keepAlive,
            numPredict: profile.numPredict,
            temperature: profile.temperature,
            generationOptions: profile.generationOptions,
            notes: profile.notes,
            purpose: profile.purpose
        )
        let applied = AppliedRuntimeProfile(
            profile: selectedModelProfile,
            currentModel: selectedModelName,
            modelMaxContext: modelMaxContext
        )
        return ModelWarmRequest(
            model: applied.model,
            keepAlive: applied.keepAlive,
            numCtx: applied.numCtx,
            options: applied.options,
            statusDetail: "keep_alive \(applied.keepAlive), \(warmContextStatus(from: applied.contextStatus))"
        )
    }

    private static func warmContextStatus(from contextStatus: String) -> String {
        switch contextStatus {
        case "Using Ollama model default context.":
            return "model default context."
        default:
            return contextStatus
                .replacingOccurrences(of: " from low ram policy.", with: " from profile policy.")
                .replacingOccurrences(of: " from balanced policy.", with: " from profile policy.")
                .replacingOccurrences(of: " from max known policy.", with: " from profile policy.")
        }
    }
}
