import Foundation

/// Deterministic spoken-punctuation rules (spec item 5): "punkt" → ".",
/// "new paragraph" → a blank line, etc. Runs BEFORE the LLM (and instead of it
/// in raw mode) so the basics never depend on model quality. Word-boundary
/// matching only - "kommandant" and "periodic" stay untouched.
public enum SpokenPunctuation {
    /// (cue, replacement, attachesToPreviousWord)
    private static let de: [(String, String, Bool)] = [
        ("neuer absatz", "\n\n", false),
        ("neue zeile", "\n", false),
        ("punkt", ".", true),
        ("komma", ",", true),
        ("fragezeichen", "?", true),
        ("ausrufezeichen", "!", true),
        ("doppelpunkt", ":", true),
        ("semikolon", ";", true),
        ("gedankenstrich", "  - ", true),
    ]
    private static let en: [(String, String, Bool)] = [
        ("new paragraph", "\n\n", false),
        ("new line", "\n", false),
        ("period", ".", true),
        ("full stop", ".", true),
        ("comma", ",", true),
        ("question mark", "?", true),
        ("exclamation mark", "!", true),
        ("exclamation point", "!", true),
        ("colon", ":", true),
        ("semicolon", ";", true),
        ("em dash", "  - ", true),
    ]

    /// `language` "de"/"en" applies that table; nil (auto-detect) applies both.
    public static func apply(_ text: String, language: String?) -> String {
        var rules: [(String, String, Bool)] = []
        if language == nil || language == "de" { rules += de }
        if language == nil || language == "en" { rules += en }
        // Longest cues first so "exclamation mark" wins over bare "mark"-like cues.
        rules.sort { $0.0.count > $1.0.count }

        var s = text
        for (cue, mark, attaches) in rules {
            let pattern = attaches
                // Swallow the space BEFORE the cue so ". " glues to the last word.
                ? #"\s*\b"# + NSRegularExpression.escapedPattern(for: cue) + #"\b"#
                // Break cues swallow surrounding spaces entirely.
                : #"\s*\b"# + NSRegularExpression.escapedPattern(for: cue) + #"\b\s*"#
            s = s.replacingOccurrences(of: pattern, with: mark,
                                       options: [.regularExpression, .caseInsensitive])
        }
        // Tidy: no space before punctuation doubles, collapse runs of spaces.
        s = s.replacingOccurrences(of: #" +([.,!?;:])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
