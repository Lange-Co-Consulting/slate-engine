import Foundation
import Testing
@testable import SlateCore

@Suite struct OpenAIStreamTests {
    @Test func extractsDeltaContent() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        #expect(OpenAIStream.token(fromLine: line) == "Hello")
    }

    @Test func roleOnlyDeltaHasNoToken() {
        let line = #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#
        #expect(OpenAIStream.token(fromLine: line) == nil)
    }

    @Test func doneSentinel() {
        #expect(OpenAIStream.isDone("data: [DONE]"))
        #expect(OpenAIStream.isDone("data:[DONE]"))
        #expect(!OpenAIStream.isDone(#"data: {"choices":[]}"#))
        #expect(OpenAIStream.token(fromLine: "data: [DONE]") == nil)
    }

    @Test func ignoresNonDataAndEmptyLines() {
        #expect(OpenAIStream.token(fromLine: "") == nil)
        #expect(OpenAIStream.token(fromLine: ": keep-alive comment") == nil)
        #expect(OpenAIStream.token(fromLine: "event: message") == nil)
    }

    @Test func multiCharAndUnicode() {
        let line = #"data: {"choices":[{"delta":{"content":"Grüße 👋"}}]}"#
        #expect(OpenAIStream.token(fromLine: line) == "Grüße 👋")
    }

    @Test func extractsAPIErrorMessage() {
        let body = #"{"error":{"message":"Invalid API key","type":"auth"}}"#
        #expect(OpenAIStream.errorMessage(fromBody: body) == "Invalid API key")
        #expect(OpenAIStream.errorMessage(fromBody: #"{"ok":true}"#) == nil)
    }
}
