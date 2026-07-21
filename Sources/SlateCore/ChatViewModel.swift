import Foundation
import Observation

@MainActor
@Observable
public final class ChatViewModel {
    public private(set) var messages: [ChatMessage] = []
    public private(set) var streamingText: String = ""
    public private(set) var isGenerating: Bool = false
    public private(set) var lastError: GenerationError?

    private let engine: any LLMEngine
    private let registry: ToolRegistry
    private var session: ChatSession
    private var genTask: Task<Void, Never>?

    public init(engine: any LLMEngine, registry: ToolRegistry, system: String? = nil) {
        self.engine = engine
        self.registry = registry
        self.session = ChatSession(system: system)
        self.messages = session.messages
    }

    /// Starts an agent turn. Returns the task so callers/tests can await it.
    @discardableResult
    public func send(_ text: String) -> Task<Void, Never>? {
        genTask?.cancel()
        lastError = nil
        session.append(ChatMessage(role: .user, content: text))
        messages = session.messages
        streamingText = ""
        isGenerating = true

        let loop = AgentLoop(engine: engine, registry: registry)
        let snapshot = session
        let task = Task { @MainActor [weak self] in
            do {
                for try await event in loop.run(session: snapshot) {
                    guard let self else { return }
                    switch event {
                    case .token(let t):
                        self.streamingText += t
                    case .toolCall(let name, _):
                        self.streamingText += "\n[calling \(name)…]\n"
                    case .toolResult:
                        self.streamingText += "\n"
                    case .finalAnswer(let answer):
                        self.session.append(ChatMessage(role: .assistant, content: answer))
                        self.messages = self.session.messages
                    case .failed(let msg):
                        self.lastError = .executionFailedText(msg)
                    }
                }
            } catch is CancellationError {
            } catch let error as GenerationError {
                self?.lastError = error
            } catch {
                self?.lastError = .decodeFailed(-1)
            }
            self?.streamingText = ""
            self?.isGenerating = false
        }
        genTask = task
        return task
    }

    public func stop() {
        genTask?.cancel()
    }
}
