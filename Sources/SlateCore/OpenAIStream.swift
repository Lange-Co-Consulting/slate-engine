import Foundation

/// Parsing helpers for the OpenAI-compatible streaming chat API (Server-Sent
/// Events). Shared by any provider that speaks the OpenAI `/chat/completions`
/// format (OpenAI, OpenRouter, Groq, Together, local servers, …).
public enum OpenAIStream {
    /// The `[DONE]` sentinel that ends an SSE completion stream.
    public static func isDone(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "data: [DONE]" || t == "data:[DONE]"
    }

    /// The incremental text from one `data:` SSE line, or nil for keep-alives,
    /// role-only deltas, `[DONE]`, and non-data lines.
    public static func token(fromLine line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("data:"), !isDone(t) else { return nil }
        let json = String(t.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String,
              !content.isEmpty else { return nil }
        return content
    }

    /// An OpenAI-style error message from a non-streamed error body, if present.
    public static func errorMessage(fromBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = obj["error"] as? [String: Any],
              let msg = err["message"] as? String else { return nil }
        return msg
    }
}
