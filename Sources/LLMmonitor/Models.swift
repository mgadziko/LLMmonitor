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
    /// A GPU summary obtained by LLMmonitor from a machine's own hardware report.
    var gpuSummary: String?
    /// The last successful read-only hardware probe, retained for offline machines.
    var hardwareProfile: HardwareProfile?
    var isOnline = false
    var lastSeen: Date?
    var lastError: String?

    var endpoint: URL? { URL(string: "http://\(address):\(port)") }
    var statusText: String { isOnline ? "Online" : "Offline" }
    var modelSummary: String { models.isEmpty ? "—" : models.map(\.name).joined(separator: ", ") }
    var gpuDisplay: String { gpuSummary ?? "Unknown" }
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

struct HardwareProfile: Codable, Hashable, Sendable {
    /// The command that supplied this profile, not an inferred machine type.
    var source: String
    var observedAt: Date
    var systemModel: String?
    var chip: String?
    var memory: String?
    var driverVersion: String?
    var gpus: [GPUDetails]

    var gpuSummary: String {
        var models: [(name: String, count: Int)] = []
        for gpu in gpus {
            if let index = models.firstIndex(where: { $0.name == gpu.name }) {
                models[index].count += 1
            } else {
                models.append((gpu.name, 1))
            }
        }
        return models.map { model in
            let suffix = gpus.first(where: { $0.name == model.name })?.coreCount.map { " — \($0)-core GPU" } ?? ""
            return model.count == 1 ? "\(model.name)\(suffix)" : "\(model.count)× \(model.name)"
        }.joined(separator: " + ")
    }
}

struct GPUDetails: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(name)-\(index)" }
    var index: Int
    var name: String
    var totalMemory: String?
    var usedMemory: String?
    var temperature: String?
    var utilization: String?
    var power: String?
    var coreCount: String?

    var hasLiveTelemetry: Bool {
        temperature != nil || utilization != nil || usedMemory != nil || power != nil
    }
}

extension Machine {
    static let examples: [Machine] = [
        Machine(displayName: "Cheyenne", address: "192.168.1.10", port: 11434, serverKind: .ollama, models: [LLMModel(name: "qwen3-coder:64k")], isOnline: true, lastSeen: .now),
        Machine(displayName: "Hal", address: "192.168.1.11", port: 11434, serverKind: .ollama, models: [LLMModel(name: "gpt-oss:20b")], isOnline: false, lastSeen: .now.addingTimeInterval(-7_200))
    ]
}
