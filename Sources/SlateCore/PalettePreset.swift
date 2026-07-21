import Foundation

/// A named color palette a user can apply in one tap. A preset is just the six
/// palette hexes - every ink/contrast color is derived from them (see
/// `SlatePalette`), so any preset is guaranteed readable. Built-ins are curated;
/// custom presets are what the user saves from the current colors.
public struct PalettePreset: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var canvasHex: String
    public var surfaceHex: String
    public var accentHex: String
    public var userBubbleHex: String
    public var assistantBubbleHex: String
    public var toolBubbleHex: String

    public init(id: String = UUID().uuidString, name: String,
                canvasHex: String, surfaceHex: String, accentHex: String,
                userBubbleHex: String, assistantBubbleHex: String, toolBubbleHex: String) {
        self.id = id
        self.name = name
        self.canvasHex = canvasHex
        self.surfaceHex = surfaceHex
        self.accentHex = accentHex
        self.userBubbleHex = userBubbleHex
        self.assistantBubbleHex = assistantBubbleHex
        self.toolBubbleHex = toolBubbleHex
    }

    /// The representative colors for a compact swatch chip: background, accent,
    /// and your-message bubble.
    public var swatchHexes: [String] { [canvasHex, accentHex, userBubbleHex] }

    /// Curated palettes, each cohesive across canvas / surface / accent / the three
    /// message bubbles. Ordered so the Slate default (Aurora) leads. Deliberately
    /// no neon/lime in-app (settled visual direction) - rich, native-Mac hues.
    public static let builtins: [PalettePreset] = [
        PalettePreset(id: "aurora", name: "Aurora",
                      canvasHex: "#5752C7", surfaceHex: "#2E6F78", accentHex: "#9B8CFF",
                      userBubbleHex: "#6F5EEA", assistantBubbleHex: "#2B3548", toolBubbleHex: "#3D4657"),
        PalettePreset(id: "evergreen", name: "Evergreen",
                      canvasHex: "#1C5B41", surfaceHex: "#123D31", accentHex: "#3FCF8E",
                      userBubbleHex: "#2E9E6B", assistantBubbleHex: "#17241E", toolBubbleHex: "#22362C"),
        PalettePreset(id: "ember", name: "Ember",
                      canvasHex: "#9A3E12", surfaceHex: "#5C2B12", accentHex: "#FB923C",
                      userBubbleHex: "#E87A1E", assistantBubbleHex: "#261C15", toolBubbleHex: "#38291D"),
        PalettePreset(id: "ocean", name: "Ocean",
                      canvasHex: "#1E4FA0", surfaceHex: "#123763", accentHex: "#5BA8FF",
                      userBubbleHex: "#2C6FE0", assistantBubbleHex: "#16202F", toolBubbleHex: "#223247"),
        PalettePreset(id: "rose", name: "Rosé",
                      canvasHex: "#A03A6E", surfaceHex: "#5E2444", accentHex: "#F472B6",
                      userBubbleHex: "#D9508F", assistantBubbleHex: "#241922", toolBubbleHex: "#362430"),
        PalettePreset(id: "graphite", name: "Graphite",
                      canvasHex: "#3C3F47", surfaceHex: "#2A2D33", accentHex: "#6B7CE8",
                      userBubbleHex: "#4E5BC8", assistantBubbleHex: "#23252B", toolBubbleHex: "#31343B"),
        PalettePreset(id: "slate", name: "Slate",
                      canvasHex: "#33465C", surfaceHex: "#22303F", accentHex: "#7CA9E6",
                      userBubbleHex: "#47698F", assistantBubbleHex: "#1A2029", toolBubbleHex: "#28323F"),
        PalettePreset(id: "nord", name: "Nord",
                      canvasHex: "#3B4252", surfaceHex: "#2E3440", accentHex: "#88C0D0",
                      userBubbleHex: "#5E81AC", assistantBubbleHex: "#232830", toolBubbleHex: "#333B49"),
        PalettePreset(id: "amethyst", name: "Amethyst",
                      canvasHex: "#5E2E86", surfaceHex: "#3C1E57", accentHex: "#C084FC",
                      userBubbleHex: "#8B54D6", assistantBubbleHex: "#211A2C", toolBubbleHex: "#322446"),
        PalettePreset(id: "lagoon", name: "Lagoon",
                      canvasHex: "#0F5D63", surfaceHex: "#0B3E42", accentHex: "#34D3BE",
                      userBubbleHex: "#1C8E88", assistantBubbleHex: "#132120", toolBubbleHex: "#1C302E"),
        PalettePreset(id: "crimson", name: "Crimson",
                      canvasHex: "#8E2A2A", surfaceHex: "#571B1B", accentHex: "#F87171",
                      userBubbleHex: "#C7443F", assistantBubbleHex: "#241616", toolBubbleHex: "#35201F"),
        PalettePreset(id: "honey", name: "Honey",
                      canvasHex: "#7A5A12", surfaceHex: "#4E3A0E", accentHex: "#FBBF24",
                      userBubbleHex: "#C99A2E", assistantBubbleHex: "#211C12", toolBubbleHex: "#322A1A"),
    ]
}
