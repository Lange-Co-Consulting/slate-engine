import Testing
@testable import SlateCore

@Test func chatMessageStoresRoleAndContent() {
    let m = ChatMessage(role: .user, content: "hi")
    #expect(m.role == .user)
    #expect(m.content == "hi")
    #expect(ChatMessage.Role.assistant.rawValue == "assistant")
}
