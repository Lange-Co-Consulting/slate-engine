import Foundation

/// Renders a conversation as portable Markdown - the shareable/archivable form.
public enum ConversationExport {
    public static func markdown(title: String, model: String, date: String,
                                messages: [ChatMessage]) -> String {
        var out = "# \(title)\n\n_\(model) · \(date)_\n"
        for m in messages where m.role == .user || m.role == .assistant {
            let who = m.role == .user ? "**You**" : "**Slate**"
            out += "\n---\n\n\(who)\n\n"
            if let img = m.imagePath, !img.isEmpty {
                out += "![generated image](\(img))\n"
            }
            let body = m.role == .assistant ? Reasoning.strip(m.content) : m.content
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out += trimmed + "\n" }
        }
        return out
    }
}
