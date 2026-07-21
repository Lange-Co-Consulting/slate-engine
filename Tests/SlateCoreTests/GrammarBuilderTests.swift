import Testing
@testable import SlateCore

@Test func buildsEagerAgentGrammar() {
    let g = GrammarBuilder.agentGrammar(toolNames: ["read_file", "edit", "finish"])
    #expect(g.triggerPatterns.isEmpty)   // eager: enforced from token 1 → JSON always valid/escaped
    #expect(g.root == "root")
    #expect(g.gbnf.contains("<tool_call>"))
    #expect(g.gbnf.contains("</tool_call>"))
    // tool names are baked into the grammar so the model can't invent one
    #expect(g.gbnf.contains("read_file"))
    #expect(g.gbnf.contains("edit"))
    #expect(g.gbnf.contains("finish"))
    // multiline rule text → real newlines between rules
    #expect(g.gbnf.contains("\n"))
}

@Test func agentGrammarFallsBackToFinishWhenEmpty() {
    let g = GrammarBuilder.agentGrammar(toolNames: [])
    #expect(g.gbnf.contains("finish"))
}
