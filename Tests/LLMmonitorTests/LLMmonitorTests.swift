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

@Test func resolvesLlamaServerAliasToLoadedGGUFName() throws {
    let response = Data("""
    {"data":[{"id":"greenlotus-qwen"}]}
    """.utf8)
    let props = Data("""
    {"model_alias":"greenlotus-qwen","model_path":"/models/Qwen2.5-72B-Instruct-Q4_K_M/qwen2.5-72b-instruct-q4_k_m-00001-of-00012.gguf"}
    """.utf8)
    let models = try LLMClient.decodeOpenAICompatibleModels(from: response)
    let identified = LLMClient.modelsWithLoadedGGUFNames(models, propsData: props)
    #expect(identified.map(\.name) == ["qwen2.5-72b-instruct-q4_k_m"])
    #expect(identified.first?.apiAlias == "greenlotus-qwen")
}

@Test func leavesOtherModelsAloneWhenPropsDoNotMatch() {
    let models = [LLMModel(name: "unrelated-model")]
    let props = Data("""
    {"model_alias":"greenlotus-qwen","model_path":"/models/qwen2.5-72b-instruct-q4_k_m.gguf"}
    """.utf8)
    #expect(LLMClient.modelsWithLoadedGGUFNames(models, propsData: props) == models)
    #expect(LLMClient.modelsWithLoadedGGUFNames(models, propsData: Data("{}".utf8)) == models)
}

@Test func summarizesNVIDIASMIOutput() {
    let output = Data("""
    Tesla P100-PCIE-16GB, 16384 MiB
    Tesla P100-PCIE-16GB, 16384 MiB
    """.utf8)
    #expect(SSHHardwareProbe.nvidiaSummary(data: output) == "2× Tesla P100-PCIE-16GB")
}

@Test func summarizesSystemProfilerGPUOutput() {
    let output = Data("""
    {"SPDisplaysDataType":[{"_name":"Apple M4 Max","sppci_cores":"40","sppci_model":"Apple M4 Max","spdisplays_ndrvs":[{"_name":"Color LCD"}]}]}
    """.utf8)
    #expect(SSHHardwareProbe.macOSSummary(data: output) == "Apple M4 Max — 40-core GPU")
}

@Test func readsLiveNVIDIATelemetry() {
    let output = Data("""
    Tesla P100-PCIE-16GB, 16384, 550.54, 62, 48, 8192, 145.20
    """.utf8)
    let profile = SSHHardwareProbe.nvidiaProfile(data: output)
    #expect(profile?.gpuSummary == "Tesla P100-PCIE-16GB")
    #expect(profile?.driverVersion == "550.54")
    #expect(profile?.gpus.first?.temperature == "62 °C")
    #expect(profile?.gpus.first?.utilization == "48 %")
    #expect(profile?.gpus.first?.usedMemory == "8192 MiB")
    #expect(profile?.gpus.first?.power == "145.20 W")
}
