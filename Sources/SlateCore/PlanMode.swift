import Foundation

/// Plan-first execution for code tasks: one short planning generation before
/// the agent loop. Small local models execute long tasks far more reliably
/// with an explicit numbered plan - and the user sees the roadmap up front.
public enum PlanMode {
    public static let system = """
    You are a senior engineer planning a coding task. Produce a SHORT numbered \
    plan (3 to 8 steps) for the task below - one line per step, each a concrete \
    action in the codebase. No prose before or after, no code, just the \
    numbered steps.
    """
    public static let maxTokens = 400
    public static let temperature = 0.3

    /// System-prompt addendum for the agent loop once a plan exists.
    public static func agentAddendum(plan: String) -> String {
        """
        \n\nWork through this plan step by step, in order. Say which step you \
        are on as you go. If a step turns out to be unnecessary, say so briefly \
        and continue:\n\(plan)
        """
    }
}
