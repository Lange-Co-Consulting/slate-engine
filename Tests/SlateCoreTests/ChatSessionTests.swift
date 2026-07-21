import Testing
@testable import SlateCore

@Test func stripThinkRemovesCompleteBlocks() {
    #expect(ChatSession.stripThink("plain") == "plain")
    #expect(ChatSession.stripThink("<think>reasoning</think>answer") == "answer")
    #expect(ChatSession.stripThink("a<think>x</think>b<think>y</think>c") == "abc")
}

@Test func stripThinkRemovesDanglingOpenToEnd() {
    #expect(ChatSession.stripThink("answer<think>still thinking") == "answer")
}

@Test func stripThinkTrimsSurroundingWhitespace() {
    #expect(ChatSession.stripThink("<think>r</think>\n\n  hello  ") == "hello")
}

@Test func appendStripsThinkOnAssistantOnly() {
    var s = ChatSession()
    s.append(ChatMessage(role: .user, content: "<think>keep</think>q"))
    s.append(ChatMessage(role: .assistant, content: "<think>drop</think>a"))
    #expect(s.messages[0].content == "<think>keep</think>q") // user untouched
    #expect(s.messages[1].content == "a")                    // assistant stripped
}

@Test func systemPromptSeedsHistory() {
    let s = ChatSession(system: "You are Slate.")
    #expect(s.messages.first == ChatMessage(role: .system, content: "You are Slate."))
}
