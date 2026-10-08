import Foundation
import Observation

@MainActor @Observable
final class MachineStore {
    private(set) var machines: [Machine] = []
    var isRefreshing = false
    var scanPorts = [11434, 1234, 8080]
    private let client = LLMClient()
    private let scanner = LANScanner()
    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "LLMmonitor")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "machines.json")
        load()
    }

    func add(_ machine: Machine) { machines.append(machine); save() }
    func remove(at offsets: IndexSet) { machines.remove(atOffsets: offsets); save() }
    func remove(ids: Set<Machine.ID>) { machines.removeAll { ids.contains($0.id) }; save() }

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        for index in machines.indices {
            await refresh(id: machines[index].id)
        }
        save()
    }

    func refresh(id: UUID) async {
        guard let index = machines.firstIndex(where: { $0.id == id }) else { return }
        let original = machines[index]
        switch await client.poll(original) {
        case .success(let models):
            machines[index].models = models
            machines[index].isOnline = true
            machines[index].lastSeen = .now
            machines[index].lastError = nil
        case .failure(let error):
            machines[index].isOnline = false
            machines[index].lastError = error.message
        }
        save()
    }

    func scanLAN() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let discovered = await scanner.discover(ports: scanPorts)
        for machine in discovered {
            if let index = machines.firstIndex(where: { $0.address == machine.address && $0.port == machine.port }) {
                machines[index].displayName = machines[index].displayName == machines[index].address ? machine.displayName : machines[index].displayName
                machines[index].serverKind = machine.serverKind
                machines[index].models = machine.models
                machines[index].isOnline = true
                machines[index].lastSeen = .now
                machines[index].lastError = nil
            } else { machines.append(machine) }
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([Machine].self, from: data) else { return }
        machines = saved.map { var machine = $0; machine.isOnline = false; return machine }
    }
    private func save() { if let data = try? JSONEncoder.pretty.encode(machines) { try? data.write(to: fileURL, options: .atomic) } }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }()
}
