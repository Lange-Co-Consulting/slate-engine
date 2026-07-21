import Foundation

public struct LocalMCPServer: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectory: String?
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, executablePath: String,
                arguments: [String] = [], workingDirectory: String? = nil, enabled: Bool = true) {
        self.id = id; self.name = name; self.executablePath = executablePath
        self.arguments = arguments; self.workingDirectory = workingDirectory; self.enabled = enabled
    }
}

public struct LocalMCPTool: Equatable, Sendable {
    public let serverID: UUID
    public let serverName: String
    public let originalName: String
    public let spec: ToolSpec
    public let parameterTypes: [String: String]

    public init(serverID: UUID, serverName: String, originalName: String,
                spec: ToolSpec, parameterTypes: [String: String]) {
        self.serverID = serverID; self.serverName = serverName; self.originalName = originalName
        self.spec = spec; self.parameterTypes = parameterTypes
    }
}

public enum LocalMCPError: Error, LocalizedError, Sendable {
    case invalidExecutable
    case missingWorkingDirectory
    case launchFailed(String)
    case protocolError(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidExecutable: return "Choose an absolute, executable local MCP server binary."
        case .missingWorkingDirectory: return "Choose a working-directory scope before enabling this local MCP server."
        case .launchFailed(let message): return "MCP server failed to launch: \(message)"
        case .protocolError(let message): return "MCP protocol error: \(message)"
        case .timedOut: return "The local MCP server timed out."
        }
    }
}

/// Minimal MCP stdio client. Every server process is wrapped in a macOS sandbox
/// profile that denies all network access; no HTTP/SSE transport is supported.
public actor LocalMCPClient {
    private static let maxTools = 128
    private static let maxParameters = 64
    private static let maxArgumentBytes = 64 * 1_024
    public init() {}

    public func discover(server: LocalMCPServer) async throws -> [LocalMCPTool] {
        try await Task.detached(priority: .utility) {
            let session = try MCPStdioSession(server: server)
            defer { session.close() }
            try session.initialize()
            let response = try session.request(id: 2, method: "tools/list", params: [:])
            return try Self.parseTools(response, server: server)
        }.value
    }

    public func call(server: LocalMCPServer, tool: LocalMCPTool,
                     arguments: [String: String]) async throws -> String {
        guard arguments.count <= Self.maxParameters,
              arguments.allSatisfy({ $0.key.utf8.count <= 128 && $0.value.utf8.count <= Self.maxArgumentBytes }) else {
            throw LocalMCPError.protocolError("tool arguments exceed Slate's local safety limits")
        }
        return try await Task.detached(priority: .userInitiated) {
            let session = try MCPStdioSession(server: server)
            defer { session.close() }
            try session.initialize()
            var converted: [String: Any] = [:]
            for (name, value) in arguments {
                switch tool.parameterTypes[name] {
                case "integer": converted[name] = Int(value) ?? value
                case "number": converted[name] = Double(value) ?? value
                case "boolean": converted[name] = ["true", "1", "yes"].contains(value.lowercased())
                case "object", "array":
                    converted[name] = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) ?? value
                default: converted[name] = value
                }
            }
            let response = try session.request(
                id: 2, method: "tools/call",
                params: ["name": tool.originalName, "arguments": converted]
            )
            guard let result = response["result"] as? [String: Any] else {
                throw LocalMCPError.protocolError("missing tool result")
            }
            if result["isError"] as? Bool == true {
                throw LocalMCPError.protocolError(Self.contentText(result))
            }
            return Self.contentText(result)
        }.value
    }

    static func parseTools(_ response: [String: Any], server: LocalMCPServer) throws -> [LocalMCPTool] {
        guard let result = response["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]] else {
            throw LocalMCPError.protocolError("tools/list returned no tools")
        }
        guard tools.count <= maxTools else {
            throw LocalMCPError.protocolError("tools/list returned too many tools")
        }
        return tools.compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty, name.utf8.count <= 128,
                  !name.contains("\0") else { return nil }
            let schema = item["inputSchema"] as? [String: Any]
            let properties = schema?["properties"] as? [String: [String: Any]] ?? [:]
            let required = Set(schema?["required"] as? [String] ?? [])
            guard properties.count <= maxParameters else { return nil }
            let parameters = properties.keys.sorted().map { key in
                ToolParameter(name: key,
                              description: String((properties[key]?["description"] as? String ?? "").prefix(1_000)),
                              required: required.contains(key))
            }
            let prefix = (server.name + "_" + name).lowercased()
                .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
            let types = properties.mapValues { $0["type"] as? String ?? "string" }
            return LocalMCPTool(
                serverID: server.id, serverName: server.name, originalName: name,
                spec: ToolSpec(name: "mcp_" + prefix,
                               description: "Local MCP · \(server.name): " + String((item["description"] as? String ?? name).prefix(4_000)),
                               parameters: parameters),
                parameterTypes: types
            )
        }
    }

    private static func contentText(_ result: [String: Any]) -> String {
        let blocks = result["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n")
        return text.isEmpty ? "(local tool returned no text)" : String(text.prefix(1_000_000))
    }
}

private final class MCPStdioSession: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var readBuffer = Data()
    private var timeoutWork: DispatchWorkItem?
    private let scratch: URL

    init(server: LocalMCPServer) throws {
        let executableURL = Self.physicalURL(URL(fileURLWithPath: server.executablePath))
        let path = executableURL.path
        guard server.name.utf8.count <= 100, server.arguments.count <= 32,
              server.arguments.allSatisfy({ $0.utf8.count <= 4_096 && !$0.contains("\0") }),
              path.hasPrefix("/"), path.utf8.count <= 4_096, FileManager.default.isExecutableFile(atPath: path),
              !["sh", "bash", "zsh", "fish"].contains(URL(fileURLWithPath: path).lastPathComponent) else {
            throw LocalMCPError.invalidExecutable
        }
        guard let rawScope = server.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawScope.isEmpty, rawScope.utf8.count <= 4_096, !rawScope.contains("\0") else {
            throw LocalMCPError.missingWorkingDirectory
        }
        let scope = Self.physicalURL(URL(fileURLWithPath: rawScope))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scope.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalMCPError.missingWorkingDirectory
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw LocalMCPError.launchFailed("macOS sandbox-exec is unavailable")
        }
        let scratchRoot = URL.applicationSupportDirectory.appendingPathComponent("Slate/MCPScratch", isDirectory: true)
        try PrivateStorage.ensureDirectory(scratchRoot)
        scratch = scratchRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try PrivateStorage.ensureDirectory(scratch)
        try PrivateStorage.ensureDirectory(scratch.appendingPathComponent("home", isDirectory: true))
        try PrivateStorage.ensureDirectory(scratch.appendingPathComponent("tmp", isDirectory: true))

        // A local tool gets exactly the scope the user selected, an empty HOME
        // and system runtimes. Slate data and the rest of the account are never
        // mounted into the child process.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", Self.sandboxProfile(scope: scope, scratch: scratch, executable: path), path] + server.arguments
        process.currentDirectoryURL = scope
        process.environment = [
            "HOME": scratch.appendingPathComponent("home", isDirectory: true).path,
            "TMPDIR": scratch.appendingPathComponent("tmp", isDirectory: true).path,
            "PWD": scope.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "en_US.UTF-8",
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw LocalMCPError.launchFailed(error.localizedDescription) }
        let work = DispatchWorkItem { [weak process] in
            if process?.isRunning == true { process?.terminate() }
        }
        timeoutWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: work)
    }

    func initialize() throws {
        _ = try request(id: 1, method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "Slate", "version": "1"]
        ])
        try notify(method: "notifications/initialized", params: [:])
    }

    func request(id: Int, method: String, params: [String: Any]) throws -> [String: Any] {
        try write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        while true {
            let response = try readMessage()
            if let responseID = response["id"] as? Int, responseID == id {
                if let error = response["error"] as? [String: Any] {
                    throw LocalMCPError.protocolError(error["message"] as? String ?? "unknown server error")
                }
                return response
            }
        }
    }

    func notify(method: String, params: [String: Any]) throws {
        try write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        guard data.count <= 256 * 1_024 else {
            throw LocalMCPError.protocolError("request exceeds Slate's local safety limit")
        }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func readMessage() throws -> [String: Any] {
        while true {
            if let newline = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer[..<newline]
                readBuffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                return object
            }
            guard process.isRunning else { throw LocalMCPError.protocolError("server exited") }
            guard let next = try output.fileHandleForReading.read(upToCount: 65_536), !next.isEmpty else {
                throw process.isRunning ? LocalMCPError.timedOut : LocalMCPError.protocolError("server closed stdout")
            }
            readBuffer.append(next)
            if readBuffer.count > 2_000_000 { throw LocalMCPError.protocolError("response too large") }
        }
    }

    func close() {
        timeoutWork?.cancel()
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: scratch)
    }

    private static func sandboxProfile(scope: URL, scratch: URL, executable: String) -> String {
        func literal(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n") + "\""
        }
        let system = ["/System", "/usr", "/bin", "/sbin", "/Library/Apple", "/usr/local", "/opt/homebrew", "/dev/null", "/dev/urandom"]
            .map { "(subpath \(literal($0)))" }.joined(separator: "\n  ")
        return """
        (version 1)
        ;; Apple's runtime baseline is needed for inherited stdio descriptors
        ;; and platform binaries. The explicit deny below takes precedence over
        ;; its narrow syslog rule, so the server still has no network access.
        (import "system.sb")
        (deny default)
        (allow process-exec)
        (allow process-fork)
        (allow signal (target self))
        (allow process-info-pidinfo (target self))
        (allow sysctl-read)
        (allow file-read*
          \(system)
          (literal \(literal(executable)))
          (subpath \(literal(scope.path)))
          (subpath \(literal(scratch.path))))
        (allow file-read-metadata file-test-existence
          (path-ancestors \(literal(scope.path)))
          (path-ancestors \(literal(scratch.path))))
        (allow file-write*
          (subpath \(literal(scope.path)))
          (subpath \(literal(scratch.path))))
        (deny network*)
        """
    }

    /// NSURL retains `/var` while Seatbelt checks the physical `/private/var`
    /// path. Normalize only the OS-owned compatibility aliases, never an
    /// arbitrary user-controlled symlink.
    private static func physicalURL(_ url: URL) -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = resolved.path
        let aliases = ["/var": "/private/var", "/tmp": "/private/tmp", "/etc": "/private/etc"]
        for (logical, physical) in aliases where path == logical || path.hasPrefix(logical + "/") {
            return URL(fileURLWithPath: physical + path.dropFirst(logical.count), isDirectory: resolved.hasDirectoryPath)
        }
        return resolved
    }
}
