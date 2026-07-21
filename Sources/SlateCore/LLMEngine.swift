import Foundation

public struct GrammarSpec: Sendable, Equatable {
    public let gbnf: String
    public let triggerPatterns: [String]   // empty => eager; non-empty => lazy
    public let root: String
    public init(gbnf: String, triggerPatterns: [String] = [], root: String = "root") {
        self.gbnf = gbnf
        self.triggerPatterns = triggerPatterns
        self.root = root
    }
}

/// A source of streamed completions. Implemented by the real `LlamaEngine`
/// (an actor) and by test doubles. The method is `async` so call sites are
/// uniform whether the conformer is an actor or a value type.
public struct GenOptions: Sendable, Equatable {
    public var temperature: Double
    public var maxTokens: Int
    /// Cloud (Claude Code) passthrough: the project dir to run in, the CLI session
    /// to resume for continuity, and the permission mode to map onto its flags.
    /// Ignored by the local llama engine.
    public var workingDirectory: String?
    public var claudeSessionId: String?
    public var openCodeSessionId: String?
    public var permissionMode: PermissionMode?
    /// The global explicit safety latch. Only Autopilot may honor it.
    public var skipPermissions: Bool
    /// Cloud model alias (opus/sonnet/haiku) and a per-conversation system-prompt
    /// to append; both ignored by the local engine.
    public var claudeModel: String?
    public var systemPromptOverride: String?
    /// Cloud thinking budget (Claude Code `MAX_THINKING_TOKENS`). nil → CLI default.
    public var maxThinkingTokens: Int?
    /// Allow the passthrough agent (Claude Code / OpenCode) to use its WebSearch /
    /// WebFetch tools this turn. Off by default (offline-first); forced off in Silent Mode.
    public var webSearchEnabled: Bool
    public init(temperature: Double = 0.7, maxTokens: Int = 2048,
                workingDirectory: String? = nil, claudeSessionId: String? = nil,
                openCodeSessionId: String? = nil,
                permissionMode: PermissionMode? = nil,
                skipPermissions: Bool = false,
                claudeModel: String? = nil, systemPromptOverride: String? = nil,
                maxThinkingTokens: Int? = nil, webSearchEnabled: Bool = false) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.workingDirectory = workingDirectory
        self.claudeSessionId = claudeSessionId
        self.openCodeSessionId = openCodeSessionId
        self.permissionMode = permissionMode
        self.skipPermissions = skipPermissions
        self.claudeModel = claudeModel
        self.systemPromptOverride = systemPromptOverride
        self.maxThinkingTokens = maxThinkingTokens
        self.webSearchEnabled = webSearchEnabled
    }
}

public protocol LLMEngine: Sendable {
    func generate(messages: [ChatMessage], grammar: GrammarSpec?, options: GenOptions) async -> AsyncThrowingStream<String, Error>
    /// True if the loaded model can consume images (a multimodal projector is attached).
    var isVision: Bool { get }
    /// True for engines that run their OWN agent loop + tools (Cloud / Claude Code):
    /// Slate streams `generate()` directly instead of wrapping it in its AgentLoop.
    var isPassthroughAgent: Bool { get }
    /// Context window in use, and the model's trained maximum (0 if unknown).
    var contextWindow: Int { get }
    var trainedContext: Int { get }
    /// True if the engine can run web search/fetch tools (the cloud passthrough agents).
    var supportsWebSearch: Bool { get }
    /// Cooperative stop: `requestStop()` makes the in-flight generation loop break
    /// promptly (checked directly, independent of Task/stream cancellation, which is
    /// unreliable while the producer is actively yielding). `clearStop()` re-arms it
    /// at the start of a new turn.
    func requestStop()
    func clearStop()
}

public extension LLMEngine {
    /// Text-only by default; vision-capable engines override.
    var isVision: Bool { false }
    var isPassthroughAgent: Bool { false }
    var contextWindow: Int { 0 }
    var trainedContext: Int { 0 }
    var supportsWebSearch: Bool { false }
    func requestStop() {}
    func clearStop() {}

    func generate(messages: [ChatMessage]) async -> AsyncThrowingStream<String, Error> {
        await generate(messages: messages, grammar: nil, options: GenOptions())
    }
    func generate(messages: [ChatMessage], grammar: GrammarSpec?) async -> AsyncThrowingStream<String, Error> {
        await generate(messages: messages, grammar: grammar, options: GenOptions())
    }
}

public enum GenerationError: Error, Equatable, Sendable {
    case modelLoadFailed
    case contextCreationFailed
    case tokenizationFailed
    case decodeFailed(Int32)
    case grammarParseFailed
    case executionFailedText(String)
}
