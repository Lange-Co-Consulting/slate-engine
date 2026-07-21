import Foundation
@testable import SlateCore

/// Emits the given chunks in order, optionally finishing with an error.
struct FakeEngine: LLMEngine {
    let chunks: [String]
    let failWith: GenerationError?

    init(chunks: [String], failWith: GenerationError? = nil) {
        self.chunks = chunks
        self.failWith = failWith
    }

    func generate(messages: [ChatMessage], grammar: GrammarSpec?, options: GenOptions) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    if Task.isCancelled { break }
                    continuation.yield(chunk)
                    await Task.yield()
                }
                if let failWith {
                    continuation.finish(throwing: failWith)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
