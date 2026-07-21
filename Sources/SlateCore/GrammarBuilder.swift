import Foundation

public enum GrammarBuilder {
    /// EAGER tool-call grammar (Hermes/Qwen-native JSON). Enforced from the first token,
    /// so EVERY agent turn is exactly one valid `<tool_call>{ "name": …, "arguments": {…} }
    /// </tool_call>`. This is the reliable fix for the JSON-escaping failure: a lazy
    /// (trigger-on-`<tool_call>`) grammar did NOT engage for some models (e.g. Qwen3.5,
    /// where `<tool_call>` is a single special token), so they emitted UNescaped quotes
    /// inside the content string → invalid JSON → the tool call silently failed and got
    /// dumped as text. Eager guarantees the string rule is active, forcing `\"`/`\n`
    /// escaping, so big HTML/code content is always valid JSON.
    ///
    /// The model ends a task by calling `finish` (there is no free-text turn under an
    /// eager grammar). Chosen because the operator's models are non-reasoning (reasoning
    /// OFF by default); an eager grammar can make a reasoning-first model fight the
    /// constraint, so if such a model becomes primary, revisit (optional think-prefix).
    public static func agentGrammar(toolNames: [String]) -> GrammarSpec {
        // Each name becomes the GBNF literal for a JSON string, e.g.  "\"edit\""
        let names = (toolNames.isEmpty ? ["finish"] : toolNames)
            .map { "\"\\\"" + $0 + "\\\"\"" }
            .joined(separator: " | ")
        let gbnf = #"""
        root     ::= "<tool_call>" ws "{" ws "\"name\"" ws ":" ws name ws "," ws "\"arguments\"" ws ":" ws object ws "}" ws "</tool_call>"
        name     ::= \#(names)
        object   ::= "{" ws "}" | "{" ws pair (ws "," ws pair)* ws "}"
        pair     ::= string ws ":" ws string
        string   ::= "\"" char* "\""
        char     ::= [^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" hex hex hex hex)
        hex      ::= [0-9a-fA-F]
        ws       ::= [ \t\n]*
        """#
        // Eager: enforce from the first token so JSON escaping is always applied.
        return GrammarSpec(gbnf: gbnf, triggerPatterns: [], root: "root")
    }
}
