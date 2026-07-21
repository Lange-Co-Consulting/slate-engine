import Foundation
import Testing
@testable import SlateCore

@Suite struct LocalMCPTests {
    @Test func parsesAndNamespacesToolDefinitions() throws {
        let server = LocalMCPServer(id: UUID(), name: "Files Local", executablePath: "/bin/echo")
        let response: [String: Any] = ["result": ["tools": [[
            "name": "find",
            "description": "Find a local note",
            "inputSchema": [
                "type": "object",
                "properties": ["query": ["type": "string", "description": "Text"]],
                "required": ["query"]
            ]
        ]]]]
        let tools = try LocalMCPClient.parseTools(response, server: server)
        #expect(tools.count == 1)
        #expect(tools[0].spec.name == "mcp_files_local_find")
        #expect(tools[0].spec.parameters == [.init(name: "query", description: "Text", required: true)])
    }

    @Test func rejectsShellAsServerExecutable() async {
        let client = LocalMCPClient()
        let server = LocalMCPServer(name: "unsafe", executablePath: "/bin/sh", arguments: ["-c", "echo nope"])
        await #expect(throws: LocalMCPError.self) { try await client.discover(server: server) }
    }

    @Test func rejectsServerWithoutExplicitFilesystemScope() async {
        let client = LocalMCPClient()
        let server = LocalMCPServer(name: "unscoped", executablePath: "/bin/echo")
        await #expect(throws: LocalMCPError.self) { try await client.discover(server: server) }
    }
}
