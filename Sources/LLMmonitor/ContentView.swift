import SwiftUI

struct ContentView: View {
    @Bindable var store: MachineStore
    @State private var selection: Machine.ID?
    @State private var showingAddMachine = false
    @State private var librarySortOrder = [KeyPathComparator(\Machine.ipSortKey)]

    var body: some View {
        NavigationSplitView {
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
            VStack(spacing: 0) {
                summary
                Table(store.machines, selection: $selection) {
                    TableColumn("Machine") { Text($0.displayName) }
                    TableColumn("Status") { StatusBadge(machine: $0) }.width(min: 76, ideal: 90)
                    TableColumn("Server") { Text($0.serverKind.rawValue) }.width(min: 120, ideal: 150)
                    TableColumn("Address") { Text("\($0.address):\($0.port)").textSelection(.enabled) }.width(min: 150, ideal: 170)
                    TableColumn("Installed Models") { Text($0.modelSummary).lineLimit(1) }.width(min: 260, ideal: 420)
                    TableColumn("Last Seen") { Text($0.lastSeenText) }.width(min: 100, ideal: 130)
                }
                .contextMenu(forSelectionType: Machine.ID.self) { ids in
                    Button("Refresh") { Task { for id in ids { await store.refresh(id: id) } } }
                    Button("Remove", role: .destructive) { store.remove(ids: ids) }
                } primaryAction: { ids in selection = ids.first }
            }
            .navigationTitle(selection.flatMap { id in store.machines.first { $0.id == id }?.displayName } ?? "Machines")
        }
        .sheet(isPresented: $showingAddMachine) { AddMachineView(store: store) }
        .task { await store.refreshAll() }
        .background(WindowFramePersistence().frame(width: 0, height: 0))
    }

    private var sortedLibraryMachines: [Machine] {
        store.machines.sorted(using: librarySortOrder)
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
