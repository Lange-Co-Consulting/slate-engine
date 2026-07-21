import Foundation

public enum AgentEvent: Sendable {
    case token(String)                       // streamed token of the current turn
    case toolCall(name: String, arguments: [String: String])
    case toolResult(name: String, output: String)
    case finalAnswer(String)
    case failed(String)
}

public struct AgentLoop: Sendable {
    private let engine: any LLMEngine
    private let registry: ToolRegistry
    private let maxIterations: Int
    private let options: GenOptions

    public init(engine: any LLMEngine, registry: ToolRegistry, maxIterations: Int = 12, options: GenOptions = GenOptions()) {
        self.engine = engine
        self.registry = registry
        self.maxIterations = maxIterations
        self.options = options
    }

    public func run(session: ChatSession) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var working = session
                // Eager grammar constrained to the real tools + the `finish` control verb.
                let grammar = GrammarBuilder.agentGrammar(toolNames: registry.specs.map(\.name) + ["finish"])
                do {
                    for _ in 0..<maxIterations {
                        try Task.checkCancellation()
                        // Collect one full assistant turn (one tool call).
                        var buffer = ""
                        // Trim the growing tool-result history to the model's window so a
                        // long agentic run (many steps) never overflows mid-loop.
                        let promptMessages = engine.contextWindow > 0
                            ? ContextBudget.trim(working.messagesForPrompt(),
                                approxTokenBudget: max(engine.contextWindow - options.maxTokens - 256,
                                                       engine.contextWindow / 2)).kept
                            : working.messagesForPrompt()
                        for try await chunk in await engine.generate(
                            messages: promptMessages, grammar: grammar, options: options) {
                            buffer += chunk
                            continuation.yield(.token(chunk))
                            if buffer.contains("</tool_call>") { break } // stop eagerly on a complete call
                        }

                        let calls = ToolCallParser.parse(buffer)
                        guard !calls.isEmpty else {
                            // Eager grammar guarantees every turn is a
                            // `<tool_call>…</tool_call>` block. Landing here means
                            // it did not parse: truncated mid-JSON (token limit),
                            // malformed JSON inside the tags, or the grammar did
                            // not engage. NEVER dump the raw buffer into the chat.
                            if buffer.contains("<tool_call") || buffer.contains("<function=") || buffer.contains("call:") {
                                continuation.yield(.failed(
                                    "The reply was cut off or malformed in the middle of a tool call. Raise “Max tokens” in Settings (⌘,) and try again - big file writes need headroom."))
                            } else {
                                // No tool markers at all: the grammar did not engage
                                // (e.g. a grammar-free engine or a test double). Only
                                // then is treating the buffer as a plain answer safe.
                                continuation.yield(.finalAnswer(ChatSession.stripThink(buffer)))
                            }
                            continuation.finish(); return
                        }
                        working.append(ChatMessage(role: .assistant, content: buffer))
                        for call in calls {
                            // `finish` is a control verb, not a registered tool: it ends the turn.
                            if call.name == "finish" {
                                let msg = call.arguments["message"] ?? call.arguments["text"]
                                       ?? call.arguments["answer"] ?? ""
                                continuation.yield(.finalAnswer(msg))
                                continuation.finish(); return
                            }
                            continuation.yield(.toolCall(name: call.name, arguments: call.arguments))
                            let output: String
                            do {
                                output = try await registry.dispatch(name: call.name, arguments: call.arguments)
                            } catch {
                                output = "ERROR: \(error)"  // fed back so the model can self-correct
                            }
                            continuation.yield(.toolResult(name: call.name, output: output))
                            // Tool output is data from the workspace, never a trusted
                            // instruction. The delimiter makes that trust boundary
                            // explicit even for models vulnerable to prompt injection.
                            let untrusted = """
                            <<<UNTRUSTED_TOOL_OUTPUT name=\(call.name)>>>
                            \(output)
                            <<<END_UNTRUSTED_TOOL_OUTPUT>>>
                            """
                            working.append(ChatMessage(role: .tool, content: untrusted))
                        }
                        // re-enter with tool results in context
                    }
                    // Hit the iteration cap without a final answer.
                    continuation.yield(.failed("Reached the step limit (\(maxIterations) steps). Work done so far is saved - send \"continue\" to keep going, or raise Agent steps in Settings."))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.yield(.failed("\(error)"))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
