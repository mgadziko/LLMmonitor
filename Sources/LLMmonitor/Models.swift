import Foundation

struct LLMModel: Codable, Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    var sizeBytes: Int64?
    var modifiedAt: Date?
    var contextLength: Int?
}

enum ServerKind: String, Codable, CaseIterable, Sendable {
    case ollama = "Ollama"
    case openAICompatible = "OpenAI-compatible"
    case lmStudio = "LM Studio"
}

struct Machine: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var displayName: String
    var address: String
    var port: Int
    var serverKind: ServerKind
    var models: [LLMModel] = []
    var isOnline = false
    var lastSeen: Date?
    var lastError: String?

    var endpoint: URL? { URL(string: "http://\(address):\(port)") }
    var statusText: String { isOnline ? "Online" : "Offline" }
    var modelSummary: String { models.isEmpty ? "—" : models.map(\.name).joined(separator: ", ") }
    var lastSeenText: String { lastSeen.map { $0.formatted(.relative(presentation: .named)) } ?? "Never" }
}

extension Machine {
    static let examples: [Machine] = [
        Machine(displayName: "Cheyenne", address: "192.168.1.10", port: 11434, serverKind: .ollama, models: [LLMModel(name: "qwen3-coder:64k")], isOnline: true, lastSeen: .now),
        Machine(displayName: "Hal", address: "192.168.1.11", port: 11434, serverKind: .ollama, models: [LLMModel(name: "gpt-oss:20b")], isOnline: false, lastSeen: .now.addingTimeInterval(-7_200))
    ]
}
