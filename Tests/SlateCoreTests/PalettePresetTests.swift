import Testing
import Foundation
@testable import SlateCore

private func isHex6(_ s: String) -> Bool {
    s.count == 7 && s.hasPrefix("#") && s.dropFirst().allSatisfy { $0.isHexDigit }
}

@Test func builtinPresetsAreValidAndDistinct() {
    #expect(PalettePreset.builtins.count >= 6)
    for preset in PalettePreset.builtins {
        for hex in [preset.canvasHex, preset.surfaceHex, preset.accentHex,
                    preset.userBubbleHex, preset.assistantBubbleHex, preset.toolBubbleHex] {
            #expect(isHex6(hex), "\(preset.name) has an invalid hex: \(hex)")
        }
        #expect(preset.swatchHexes.count == 3)
    }
    // Unique ids, and the explicitly-requested green + orange presets exist.
    #expect(Set(PalettePreset.builtins.map(\.id)).count == PalettePreset.builtins.count)
    #expect(PalettePreset.builtins.contains { $0.id == "evergreen" })
    #expect(PalettePreset.builtins.contains { $0.id == "ember" })
}

@Test func presetCodableRoundTrips() {
    let preset = PalettePreset(name: "Mine", canvasHex: "#112233", surfaceHex: "#223344",
                               accentHex: "#334455", userBubbleHex: "#445566",
                               assistantBubbleHex: "#556677", toolBubbleHex: "#667788")
    let data = try! JSONEncoder().encode([preset])
    let back = try! JSONDecoder().decode([PalettePreset].self, from: data)
    #expect(back == [preset])
}
