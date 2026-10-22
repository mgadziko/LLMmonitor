import SwiftUI

struct ContentView: View {
    @Bindable var store: MachineStore
    @State private var selection: Machine.ID?
    @State private var showingAddMachine = false
    @State private var librarySortOrder = [KeyPathComparator(\Machine.ipSortKey)]
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            Table(sortedLibraryMachines, selection: $selection, sortOrder: $librarySortOrder) {
                TableColumn("Machine", value: \.displayName) { machine in
                    Label(machine.displayName, systemImage: machine.isOnline ? "desktopcomputer.and.macbook" : "desktopcomputer")
                        .foregroundStyle(machine.isOnline ? .primary : .secondary)
                }
                .width(min: 130, ideal: 165)
                TableColumn("IP Address", value: \.ipSortKey) { machine in
                    Text(machine.address).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 135)
            }
            .contextMenu(forSelectionType: Machine.ID.self) { ids in
                Button("Refresh") { Task { for id in ids { await store.refresh(id: id) } } }
                Button("Remove", role: .destructive) { store.remove(ids: ids) }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem { Button(action: { showingAddMachine = true }) { Label("Add Machine", systemImage: "plus") } }
            }
        } detail: {
            Group {
                if let selectedMachine {
                    MachineInspector(machine: selectedMachine, isRefreshing: store.isRefreshing) {
                        Task { await store.refresh(id: selectedMachine.id) }
                    } showAll: {
                        selection = nil
                    }
                } else {
                    allMachinesView
                }
            }
            .navigationTitle(selectedMachine?.displayName ?? "Machines")
        }
        .sheet(isPresented: $showingAddMachine) { AddMachineView(store: store) }
        .task { await store.refreshAll() }
        .background(WindowFramePersistence().frame(width: 0, height: 0))
    }

    private var sortedLibraryMachines: [Machine] {
        store.machines.sorted(using: librarySortOrder)
    }

    private var selectedMachine: Machine? {
        guard let selection else { return nil }
        return store.machines.first { $0.id == selection }
    }

    private var allMachinesView: some View {
        VStack(spacing: 0) {
            summary
            Table(store.machines, selection: $selection) {
                TableColumn("Machine") { Text($0.displayName) }
                TableColumn("Status") { StatusBadge(machine: $0) }.width(min: 76, ideal: 90)
                TableColumn("Server") { Text($0.serverKind.rawValue) }.width(min: 120, ideal: 150)
                TableColumn("Address") { Text("\($0.address):\($0.port)").textSelection(.enabled) }.width(min: 150, ideal: 170)
                TableColumn("GPUs") { Text($0.gpuDisplay).lineLimit(1) }.width(min: 150, ideal: 190)
                TableColumn("Installed Models") { Text($0.modelSummary).lineLimit(1) }.width(min: 260, ideal: 420)
                TableColumn("Last Seen") { Text($0.lastSeenText) }.width(min: 100, ideal: 130)
            }
            .contextMenu(forSelectionType: Machine.ID.self) { ids in
                Button("Refresh") { Task { for id in ids { await store.refresh(id: id) } } }
                Button("Remove", role: .destructive) { store.remove(ids: ids) }
            } primaryAction: { ids in selection = ids.first }
        }
    }

    private var summary: some View {
        HStack {
            let online = store.machines.filter(\.isOnline).count
            Text("\(online) online · \(store.machines.count) remembered machines")
                .foregroundStyle(.secondary)
            Spacer()
            Button { Task { await store.scanLAN() } } label: { Label("Scan LAN", systemImage: "dot.radiowaves.left.and.right") }
                .disabled(store.isRefreshing)
            Button { Task { await store.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(store.isRefreshing)
        }
        .padding()
        .background(.bar)
    }
}

private struct MachineInspector: View {
    let machine: Machine
    let isRefreshing: Bool
    let refresh: () -> Void
    let showAll: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.displayName).font(.largeTitle.weight(.semibold))
                        StatusBadge(machine: machine)
                    }
                    Spacer()
                    Button(action: showAll) { Label("All Machines", systemImage: "list.bullet") }
                    Button(action: refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(isRefreshing)
                }

                GroupBox("Connection") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        InspectorRow(label: "Address", value: "\(machine.address):\(machine.port)")
                        InspectorRow(label: "Server", value: machine.serverKind.rawValue)
                        InspectorRow(label: "Last seen", value: machine.lastSeenText)
                        if let lastError = machine.lastError {
                            InspectorRow(label: "Last error", value: lastError)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Hardware profile") {
                    if let profile = machine.hardwareProfile {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Observed \(profile.observedAt.formatted(.relative(presentation: .named)))")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(profile.source).foregroundStyle(.secondary)
                            }
                            if profile.systemModel != nil || profile.chip != nil || profile.memory != nil || profile.driverVersion != nil {
                                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                    if let systemModel = profile.systemModel { InspectorRow(label: "System", value: systemModel) }
                                    if let chip = profile.chip { InspectorRow(label: "Chip", value: chip) }
                                    if let memory = profile.memory { InspectorRow(label: "Memory", value: memory) }
                                    if let driverVersion = profile.driverVersion { InspectorRow(label: "NVIDIA driver", value: driverVersion) }
                                }
                            }
                            ForEach(profile.gpus) { gpu in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(gpu.name).font(.headline)
                                    if gpu.hasLiveTelemetry {
                                        Text("Live GPU telemetry").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                                        if let totalMemory = gpu.totalMemory { InspectorRow(label: "VRAM", value: totalMemory) }
                                        if let usedMemory = gpu.usedMemory { InspectorRow(label: "VRAM in use", value: usedMemory) }
                                        if let temperature = gpu.temperature { InspectorRow(label: "Temperature", value: temperature) }
                                        if let utilization = gpu.utilization { InspectorRow(label: "Utilization", value: utilization) }
                                        if let power = gpu.power { InspectorRow(label: "Power", value: power) }
                                        if let coreCount = gpu.coreCount { InspectorRow(label: "GPU cores", value: coreCount) }
                                    }
                                }
                                .padding(12)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No hardware profile has been obtained from this machine yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Installed models") {
                    if machine.models.isEmpty {
                        Text("No model inventory has been reported.").foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(machine.models) { model in
                                Text(model.name).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

private struct StatusBadge: View {
    let machine: Machine
    var body: some View { Label(machine.statusText, systemImage: machine.isOnline ? "checkmark.circle.fill" : "circle") .foregroundStyle(machine.isOnline ? .green : .secondary) }
}

struct AddMachineView: View {
    @Environment(\.dismiss) private var dismiss
    let store: MachineStore
    @State private var name = ""
    @State private var address = ""
    @State private var port = 11434
    @State private var kind = ServerKind.ollama

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("IP address or hostname", text: $address)
            TextField("Port", value: $port, format: .number)
            Picker("Server", selection: $kind) { ForEach(ServerKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        }
        .padding()
        .frame(width: 390)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add") { store.add(Machine(displayName: name.isEmpty ? (Machine.knownName(for: address) ?? address) : name, address: address, port: port, serverKind: kind)); dismiss() }.disabled(address.isEmpty) }
        }
    }
}

struct SettingsView: View {
    let store: MachineStore
    var body: some View { Form { Text("LLMmonitor probes Ollama, OpenAI-compatible, and LM Studio server APIs."); Text("Machine information is stored locally in Application Support.") }.padding().frame(width: 420) }
}
