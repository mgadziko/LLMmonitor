import Foundation
import Testing
@testable import LLMmonitor

@Test func machinePreservesKnownModelsWhenOffline() {
    var machine = Machine.examples[0]
    machine.isOnline = false
    #expect(machine.models.map(\.name) == ["qwen3-coder:64k"])
    #expect(machine.statusText == "Offline")
}

@Test func decodesLlamaServerModelList() throws {
    let response = Data("""
    {"models":[{"name":"greenlotus-qwen"}]}
    """.utf8)
    #expect(try LLMClient.decodeOpenAICompatibleModels(from: response).map(\.name) == ["greenlotus-qwen"])
}
