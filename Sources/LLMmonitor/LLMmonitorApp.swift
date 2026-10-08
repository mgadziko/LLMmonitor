import SwiftUI

@main
struct LLMmonitorApp: App {
    @State private var store = MachineStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1_020, minHeight: 620)
        }
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About LLMmonitor") { AboutWindowController.shared.show() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save…") { store.exportCurrentTable() }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        Settings {
            SettingsView(store: store)
        }
    }
}
