import Foundation

struct RuntimeProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var preferredModel: String
    var numCtx: Int
    var keepAlive: String
    var numPredict: Int
    var temperature: Double
    var notes: String
    var purpose: String

    static let builtIns: [RuntimeProfile] = [
        RuntimeProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Coding - Conservative",
            preferredModel: "",
            numCtx: 32768,
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.1,
            notes: "Max loaded models is an app-side note only.",
            purpose: "Stable coding assistant"
        ),
        RuntimeProfile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Long Context",
            preferredModel: "",
            numCtx: 65536,
            keepAlive: "30m",
            numPredict: 4096,
            temperature: 0.2,
            notes: "",
            purpose: "Larger project/document context"
        ),
        RuntimeProfile(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Low RAM",
            preferredModel: "",
            numCtx: 8192,
            keepAlive: "5m",
            numPredict: 2048,
            temperature: 0.2,
            notes: "",
            purpose: "Avoid keeping large models hot"
        )
    ]
}
