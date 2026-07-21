import Testing
@testable import SlateCore

private func emptyRegistry() -> ToolRegistry { ToolRegistry(tools: []) }

@MainActor
@Test func sendAccumulatesAndFinalizes() async {
    let vm = ChatViewModel(engine: FakeEngine(chunks: ["Hel", "lo"]), registry: emptyRegistry())
    await vm.send("hi")?.value
    #expect(vm.isGenerating == false)
    #expect(vm.streamingText == "")
    #expect(vm.messages == [ChatMessage(role: .user, content: "hi"),
                            ChatMessage(role: .assistant, content: "Hello")])
}

@MainActor
@Test func assistantThinkStrippedInHistory() async {
    let vm = ChatViewModel(engine: FakeEngine(chunks: ["<think>plan</think>", "done"]), registry: emptyRegistry())
    await vm.send("go")?.value
    #expect(vm.messages.last == ChatMessage(role: .assistant, content: "done"))
}

@MainActor
@Test func errorSurfacesAndClearsGenerating() async {
    let vm = ChatViewModel(engine: FakeEngine(chunks: ["partial"], failWith: .decodeFailed(-1)),
                           registry: emptyRegistry())
    await vm.send("x")?.value
    #expect(vm.isGenerating == false)
    #expect(vm.lastError == .decodeFailed(-1))
    #expect(vm.messages == [ChatMessage(role: .user, content: "x")])
}
