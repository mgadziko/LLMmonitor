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

    /// A zero-padded address gives IPv4 addresses true numerical ordering in a table.
    var ipSortKey: String {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return "~\(address)" }
        return octets.map { String(format: "%03d", $0) }.joined(separator: ".")
    }

    static func knownName(for address: String) -> String? {
        [
            "192.168.4.57": "GreenLotus",
            "192.168.4.78": "Hal",
            "192.168.4.101": "Cheyenne",
            "192.168.4.150": "BlackLotus",
            "192.168.4.164": "Organon",
            "192.168.4.165": "WhiteLotus"
        ][address]
    }
}

extension Machine {
    static let examples: [Machine] = [
        Machine(displayName: "Cheyenne", address: "192.168.1.10", port: 11434, serverKind: .ollama, models: [LLMModel(name: "qwen3-coder:64k")], isOnline: true, lastSeen: .now),
        Machine(displayName: "Hal", address: "192.168.1.11", port: 11434, serverKind: .ollama, models: [LLMModel(name: "gpt-oss:20b")], isOnline: false, lastSeen: .now.addingTimeInterval(-7_200))
    ]
}
