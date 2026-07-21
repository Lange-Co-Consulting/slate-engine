import Testing
@testable import SlateCore

@Test func grammarSpecHoldsGbnfAndTriggers() {
    let g = GrammarSpec(gbnf: "root ::= \"x\"", triggerPatterns: ["<tool_call>"], root: "root")
    #expect(g.root == "root")
    #expect(g.triggerPatterns == ["<tool_call>"])
}

@Test func roleHasToolCase() {
    #expect(ChatMessage.Role.tool.rawValue == "tool")
}
