import Testing
import Foundation
@testable import SlateCore

@Test func dispatchesToRegisteredTool() async throws {
    let spec = ToolSpec(name: "echo",
                        description: "echoes text",
                        parameters: [.init(name: "text", description: "what to echo", required: true)])
    let registry = ToolRegistry(tools: [
        RegisteredTool(spec: spec) { args in args["text"] ?? "" }
    ])
    let result = try await registry.dispatch(name: "echo", arguments: ["text": "hi"])
    #expect(result == "hi")
}

@Test func unknownToolReturnsErrorText() async {
    let registry = ToolRegistry(tools: [])
    await #expect(throws: ToolError.self) {
        _ = try await registry.dispatch(name: "nope", arguments: [:])
    }
}

@Test func specsExposedForGrammar() {
    let spec = ToolSpec(name: "read_file", description: "d",
                        parameters: [.init(name: "path", description: "p", required: true)])
    let registry = ToolRegistry(tools: [RegisteredTool(spec: spec) { _ in "" }])
    #expect(registry.specs.map(\.name) == ["read_file"])
}
