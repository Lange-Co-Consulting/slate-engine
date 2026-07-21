import Foundation

public struct ToolParameter: Sendable, Equatable {
    public let name: String
    public let description: String
    public let required: Bool
    public init(name: String, description: String, required: Bool) {
        self.name = name; self.description = description; self.required = required
    }
}

public struct ToolSpec: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]
    public init(name: String, description: String, parameters: [ToolParameter]) {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

public enum ToolError: Error, Equatable, Sendable {
    case unknownTool(String)
    case missingArgument(String)
    case executionFailed(String)
}

/// A tool spec plus its executor. Args arrive as raw strings (wire format).
public struct RegisteredTool: Sendable {
    public let spec: ToolSpec
    public let run: @Sendable ([String: String]) async throws -> String
    public init(spec: ToolSpec, run: @escaping @Sendable ([String: String]) async throws -> String) {
        self.spec = spec; self.run = run
    }
}
