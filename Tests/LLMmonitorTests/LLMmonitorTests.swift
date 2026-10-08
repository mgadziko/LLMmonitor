import Testing
@testable import LLMmonitor

@Test func machinePreservesKnownModelsWhenOffline() {
    var machine = Machine.examples[0]
    machine.isOnline = false
    #expect(machine.models.map(\.name) == ["qwen3-coder:64k"])
    #expect(machine.statusText == "Offline")
}
