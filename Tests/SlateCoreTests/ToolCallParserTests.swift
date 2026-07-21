import Testing
@testable import SlateCore

@Test func parsesSingleJSONCall() {
    let buf = """
    <tool_call>
    {"name": "read_file", "arguments": {"path": "src/main.swift"}}
    </tool_call>
    """
    let calls = ToolCallParser.parse(buf)
    #expect(calls.count == 1)
    #expect(calls[0].name == "read_file")
    #expect(calls[0].arguments["path"] == "src/main.swift")
}

@Test func roundTripsEscapedNewlinesAndAngleBrackets() {
    let buf = #"<tool_call>{"name":"write_file","arguments":{"path":"a.html","content":"<div>\n</div>\n"}}</tool_call>"#
    let calls = ToolCallParser.parse(buf)
    #expect(calls.count == 1)
    #expect(calls[0].arguments["content"] == "<div>\n</div>\n")
}

@Test func parsesMultipleCalls() {
    let buf = """
    <tool_call>{"name":"a","arguments":{"x":"1"}}</tool_call>
    <tool_call>{"name":"b","arguments":{"y":"2"}}</tool_call>
    """
    let calls = ToolCallParser.parse(buf)
    #expect(calls.map(\.name) == ["a", "b"])
    #expect(calls[1].arguments["y"] == "2")
}

@Test func coercesNonStringArgs() {
    let buf = #"<tool_call>{"name":"t","arguments":{"n":5,"b":true}}</tool_call>"#
    let calls = ToolCallParser.parse(buf)
    #expect(calls[0].arguments["n"] == "5")
    #expect(calls[0].arguments["b"] == "true")
}

@Test func toleratesMissingCloseTag() {
    let buf = #"<tool_call>{"name":"finish","arguments":{"message":"done"}}"#
    let calls = ToolCallParser.parse(buf)
    #expect(calls.count == 1)
    #expect(calls[0].arguments["message"] == "done")
}

// Alternative model formats:

@Test func parsesHarmonyCallFormatWithUnquotedKeys() {
    // gemma4-v2 emits e.g. `call:list_files {glob: "**/*"}` (note unquoted key).
    let calls = ToolCallParser.parse(#"call:list_files {glob: "**/*"}"#)
    #expect(calls.count == 1)
    #expect(calls[0].name == "list_files")
    #expect(calls[0].arguments["glob"] == "**/*")
}

@Test func parsesHarmonyCallNoArgs() {
    let calls = ToolCallParser.parse("Let me look. call: list_files")
    #expect(calls.first?.name == "list_files")
}

@Test func parsesQwenXMLFunctionFormat() {
    let buf = "<function=read_file>\n<parameter=path>\nsrc/x.swift\n</parameter>\n</function>"
    let calls = ToolCallParser.parse(buf)
    #expect(calls.count == 1)
    #expect(calls[0].name == "read_file")
    #expect(calls[0].arguments["path"] == "src/x.swift")
}

@Test func detectsToolCallPresenceSemantically() {
    #expect(ToolCallParser.containsToolCall("just a normal answer, no tools") == false)
    #expect(ToolCallParser.containsToolCall(#"<tool_call>{"name":"x","arguments":{}}</tool_call>"#) == true)
    #expect(ToolCallParser.containsToolCall(#"call:search {query: "todo"}"#) == true)
}
