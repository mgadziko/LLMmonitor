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
    private let sshHardwareProbe = SSHHardwareProbe()
    private let fileURL: URL
    private let clearsLegacyGPUHintsKey = "LLMmonitor.clearedLegacyGPUHints"

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
        if let gpuSummary = await sshHardwareProbe.gpuSummary(for: original) {
            machines[index].gpuSummary = gpuSummary
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
        let shouldClearLegacyGPUHints = !UserDefaults.standard.bool(forKey: clearsLegacyGPUHintsKey)
        machines = saved.map {
            var machine = $0
            if machine.displayName == machine.address, let knownName = Machine.knownName(for: machine.address) {
                machine.displayName = knownName
            }
            if shouldClearLegacyGPUHints {
                // GPU values from pre-telemetry builds were local fleet hints, not observed data.
                machine.gpuSummary = nil
            }
            machine.isOnline = false
            return machine
        }
        if shouldClearLegacyGPUHints {
            UserDefaults.standard.set(true, forKey: clearsLegacyGPUHintsKey)
            save()
        }
    }
    private func save() { if let data = try? JSONEncoder.pretty.encode(machines) { try? data.write(to: fileURL, options: .atomic) } }
}

/// Reads GPU inventory over an already-authorized SSH connection.
/// SSH host aliases select the appropriate key from the user's SSH configuration.
/// It never prompts for credentials or changes remote state.
actor SSHHardwareProbe {
    func gpuSummary(for machine: Machine) async -> String? {
        guard let host = Self.sshHost(for: machine.address) else { return nil }
        return await Task.detached(priority: .utility) {
            Self.readGPU(host: host)
        }.value
    }

    nonisolated static func sshHost(for address: String) -> String? {
        [
            "192.168.4.57": "greenlotus",
            "192.168.4.78": "hal",
            "192.168.4.101": "cheyenne",
            "192.168.4.150": "blacklotus",
            "192.168.4.165": "whitelotus",
            "192.168.4.164": "organon"
        ][address]
    }

    /// Uses NVIDIA's native utility when available, then macOS System Profiler.
    /// Both commands are read-only and run through the same SSH host alias.
    nonisolated private static func readGPU(host: String) -> String? {
        if let nvidiaData = runSSH(
            host: host,
            command: "nvidia-smi --query-gpu=name,memory.total --format=csv,noheader"
        ), let summary = nvidiaSummary(data: nvidiaData) {
            return summary
        }

        guard let systemProfilerData = runSSH(
            host: host,
            command: "system_profiler SPDisplaysDataType -json"
        ) else {
            return nil
        }
        return macOSSummary(data: systemProfilerData)
    }

    nonisolated private static func runSSH(host: String, command: String) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/ssh")
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=4",
            "-o", "NumberOfPasswordPrompts=0",
            "-o", "StrictHostKeyChecking=yes",
            host,
            command
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return output.fileHandleForReading.readDataToEndOfFile()
        } catch {
            return nil
        }
    }

    nonisolated static func nvidiaSummary(data: Data) -> String? {
        let names = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let name = line.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces)
                return name?.isEmpty == false ? name : nil
            }
        guard !names.isEmpty else { return nil }

        var orderedModels: [(name: String, count: Int)] = []
        for name in names {
            if let index = orderedModels.firstIndex(where: { $0.name == name }) {
                orderedModels[index].count += 1
            } else {
                orderedModels.append((name, 1))
            }
        }
        return orderedModels.map { "\($0.count)× \($0.name)" }.joined(separator: " + ")
    }

    /// Extracts the primary GPU reported by `system_profiler SPDisplaysDataType -json`.
    nonisolated static func macOSSummary(data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let displays = root["SPDisplaysDataType"] as? [[String: Any]]
        else { return nil }

        for display in displays {
            // Apple silicon reports the GPU attributes on this top-level object.
            // Its nested `spdisplays_ndrvs` objects describe attached displays.
            if let summary = macOSGPUSummary(from: display, allowsNameFallback: true) {
                return summary
            }
            guard let drivers = display["spdisplays_ndrvs"] as? [[String: Any]] else { continue }
            for driver in drivers {
                // Some external GPUs are represented by a nested PCI driver.
                // Do not use `_name` here: it can be a display name such as “Color LCD”.
                if let summary = macOSGPUSummary(from: driver, allowsNameFallback: false) {
                    return summary
                }
            }
        }
        return nil
    }

    nonisolated private static func macOSGPUSummary(
        from properties: [String: Any],
        allowsNameFallback: Bool
    ) -> String? {
        let model = properties["sppci_model"] as? String
            ?? (allowsNameFallback ? properties["_name"] as? String : nil)
        guard let model, !model.isEmpty else { return nil }

        let cores = (properties["sppci_cores"] ?? properties["spdisplays_cores"]) as? String
        if let cores, !cores.isEmpty {
            return "\(model) — \(cores)-core GPU"
        }
        return model
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }()
}
