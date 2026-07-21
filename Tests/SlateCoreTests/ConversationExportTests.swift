import Foundation
import Testing
@testable import SlateCore

@Suite struct ConversationExportTests {
    private func msg(_ role: ChatMessage.Role, _ text: String, image: String? = nil) -> ChatMessage {
        ChatMessage(role: role, content: text, imagePath: image)
    }

    @Test func rendersHeaderAndTurns() {
        let md = ConversationExport.markdown(
            title: "My chat", model: "Qwen3", date: "2026-07-11",
            messages: [msg(.system, "sys"), msg(.user, "Hi"), msg(.assistant, "Hello!")])
        #expect(md.contains("# My chat"))
        #expect(md.contains("Qwen3"))
        #expect(md.contains("2026-07-11"))
        #expect(md.contains("**You**"))
        #expect(md.contains("Hi"))
        #expect(md.contains("**Slate**"))
        #expect(md.contains("Hello!"))
        // System messages are not exported.
        #expect(!md.contains("sys"))
    }

    @Test func stripsThinkFromAssistant() {
        let md = ConversationExport.markdown(
            title: "t", model: "m", date: "d",
            messages: [msg(.assistant, "<think>planning</think>The answer.")])
        #expect(md.contains("The answer."))
        #expect(!md.contains("planning"))
    }

    @Test func rendersGeneratedImage() {
        let md = ConversationExport.markdown(
            title: "t", model: "m", date: "d",
            messages: [msg(.assistant, "", image: "/x/y.png")])
        #expect(md.contains("![generated image](/x/y.png)"))
    }

    @Test func emptyConversationStillHasHeader() {
        let md = ConversationExport.markdown(title: "Empty", model: "m", date: "d", messages: [])
        #expect(md.contains("# Empty"))
    }
}
