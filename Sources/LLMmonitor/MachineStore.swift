import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

@MainActor @Observable
final class MachineStore {
    private(set) var machines: [Machine] = []
    var isRefreshing = false
    /// Includes the fleet's dedicated OpenAI-compatible service port (11435).
    var scanPorts = [11434, 11435, 1234, 8080]
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

    func exportCurrentTable() {
        let panel = NSSavePanel()
        let formatPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        formatPicker.addItems(withTitles: ["Comma-separated values (.csv)", "Plain text (.txt)"])
        formatPicker.selectItem(at: 0)

        let accessory = NSStackView(views: [NSTextField(labelWithString: "Format:"), formatPicker])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        panel.accessoryView = accessory
        panel.nameFieldStringValue = "LLMmonitor-Machines.csv"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.canSelectHiddenExtension = true

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let format: ExportFormat = formatPicker.indexOfSelectedItem == 1 ? .text : .csv
        let url = selectedURL.pathExtension.isEmpty ? selectedURL.appendingPathExtension(format.fileExtension) : selectedURL

        do {
            try exportData(format: format).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t Save LLMmonitor Export"
            alert.runModal()
        }
    }

    private enum ExportFormat { case csv, text
        var fileExtension: String { self == .csv ? "csv" : "txt" }
    }

    private func exportData(format: ExportFormat) -> Data {
        let text: String
        switch format {
        case .csv:
            let header = ["Machine", "Status", "Server", "Address", "Installed Models", "Last Seen", "Last Error"]
            let rows = machines.map { machine in
                [machine.displayName, machine.statusText, machine.serverKind.rawValue, "\(machine.address):\(machine.port)", machine.modelSummary, machine.lastSeenText, machine.lastError ?? ""]
                    .map(Self.csvField)
                    .joined(separator: ",")
            }
            text = ([header.map(Self.csvField).joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
        case .text:
            let date = Date().formatted(date: .abbreviated, time: .standard)
            let rows = machines.map { machine in
                """
                \(machine.displayName)
                  Status: \(machine.statusText)
                  Server: \(machine.serverKind.rawValue)
                  Address: \(machine.address):\(machine.port)
                  Installed Models: \(machine.modelSummary)
                  Last Seen: \(machine.lastSeenText)
                """ + (machine.lastError.map { "\n  Last Error: \($0)" } ?? "")
            }
            text = "LLMmonitor Machine Library\nExported: \(date)\n\n" + rows.joined(separator: "\n\n") + "\n"
        }
        return Data(text.utf8)
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([Machine].self, from: data) else { return }
        machines = saved.map {
            var machine = $0
            if machine.displayName == machine.address, let knownName = Machine.knownName(for: machine.address) {
                machine.displayName = knownName
            }
            machine.isOnline = false
            return machine
        }
    }
    private func save() { if let data = try? JSONEncoder.pretty.encode(machines) { try? data.write(to: fileURL, options: .atomic) } }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }()
}
