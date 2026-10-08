import SwiftUI

@main
struct LLMmonitorApp: App {
    @State private var store = MachineStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1_020, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        Settings {
            SettingsView(store: store)
        }
    }
}
