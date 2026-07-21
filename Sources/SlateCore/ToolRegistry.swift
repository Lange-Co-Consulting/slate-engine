import Foundation

public struct ToolRegistry: Sendable {
    private let byName: [String: RegisteredTool]
    public let specs: [ToolSpec]

    public init(tools: [RegisteredTool]) {
        self.specs = tools.map(\.spec)
        self.byName = Dictionary(uniqueKeysWithValues: tools.map { ($0.spec.name, $0) })
    }

    public func dispatch(name: String, arguments: [String: String]) async throws -> String {
        guard let tool = byName[name] else { throw ToolError.unknownTool(name) }
        for p in tool.spec.parameters where p.required {
            guard arguments[p.name] != nil else { throw ToolError.missingArgument(p.name) }
        }
        return try await tool.run(arguments)
    }
}
