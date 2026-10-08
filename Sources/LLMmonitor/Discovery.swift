import Foundation
import Network

struct PollError: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

actor LLMClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: configuration)
    }

    func poll(_ machine: Machine) async -> Result<[LLMModel], PollError> {
        guard let endpoint = machine.endpoint else { return .failure(PollError(message: "Invalid address")) }
        do {
            let models: [LLMModel]
            switch machine.serverKind {
            case .ollama: models = try await ollamaModels(endpoint)
            case .openAICompatible: models = try await openAIModels(endpoint)
            case .lmStudio: models = try await lmStudioModels(endpoint)
            }
            return .success(models)
        } catch {
            return .failure(PollError(message: error.localizedDescription))
        }
    }

    private func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
        return data
    }

    private func ollamaModels(_ endpoint: URL) async throws -> [LLMModel] {
        struct Response: Decodable { let models: [Item] }
        struct Item: Decodable { let name: String; let size: Int64?; let modified_at: Date? }
        let response = try JSONDecoder.ollama.decode(Response.self, from: try await data(from: endpoint.appending(path: "api/tags")))
        return response.models.map { LLMModel(name: $0.name, sizeBytes: $0.size, modifiedAt: $0.modified_at) }.sorted { $0.name < $1.name }
    }

    private func openAIModels(_ endpoint: URL) async throws -> [LLMModel] {
        struct Response: Decodable { let data: [Item] }
        struct Item: Decodable { let id: String }
        let response = try JSONDecoder().decode(Response.self, from: try await data(from: endpoint.appending(path: "v1/models")))
        return response.data.map { LLMModel(name: $0.id) }.sorted { $0.name < $1.name }
    }

    private func lmStudioModels(_ endpoint: URL) async throws -> [LLMModel] {
        struct Response: Decodable { let data: [Item] }
        struct Item: Decodable { let id: String; let max_context_length: Int? }
        let response = try JSONDecoder().decode(Response.self, from: try await data(from: endpoint.appending(path: "api/v0/models")))
        return response.data.map { LLMModel(name: $0.id, contextLength: $0.max_context_length) }.sorted { $0.name < $1.name }
    }
}

extension JSONDecoder {
    static let ollama: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Finds responding services on the local /24 network. It only probes the configured service ports.
actor LANScanner {
    private let client = LLMClient()

    func discover(ports: [Int]) async -> [Machine] {
        guard let subnet = Self.localIPv4Subnet() else { return [] }
        let candidates = (1...254).flatMap { host in ports.map { ("\(subnet).\(host)", $0) } }
        return await withTaskGroup(of: Machine?.self, returning: [Machine].self) { group in
            for (address, port) in candidates {
                group.addTask {
                    for kind in [ServerKind.ollama, .openAICompatible, .lmStudio] {
                        let machine = Machine(displayName: address, address: address, port: port, serverKind: kind)
                        if case .success(let models) = await self.client.poll(machine) {
                            return Machine(displayName: address, address: address, port: port, serverKind: kind, models: models, isOnline: true, lastSeen: .now)
                        }
                    }
                    return nil
                }
            }
            var found: [Machine] = []
            for await machine in group { if let machine { found.append(machine) } }
            return found
        }
    }

    nonisolated static func localIPv4Subnet() -> String? {
        var addresses: [String] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard pointer.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(pointer.pointee.ifa_addr, socklen_t(pointer.pointee.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(decoding: hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
        return addresses.first(where: { !$0.hasPrefix("127.") && $0.split(separator: ".").count == 4 })?.split(separator: ".").prefix(3).joined(separator: ".")
    }
}
