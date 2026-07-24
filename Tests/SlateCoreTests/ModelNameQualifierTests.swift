import Foundation
import Testing
@testable import SlateCore

@Suite("Model name qualifier disambiguates same-looking files")
struct ModelNameQualifierTests {
    @Test("Two quants of one model prettify the same but qualify differently")
    func quantsDiffer() {
        let a = "Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"
        let b = "Qwen3-30B-A3B-Instruct-2507-Q6_K.gguf"
        #expect(ModelName.pretty(a) == ModelName.pretty(b))          // the collision Eric hit
        #expect(ModelName.qualifier(a) != ModelName.qualifier(b))    // now tellable apart
        #expect(ModelName.qualifier(a).contains("Q4_K_M"))
        #expect(ModelName.qualifier(b).contains("Q6_K"))
    }

    @Test("Gemma variants are distinguishable too")
    func gemmaVariants() {
        #expect(ModelName.qualifier("gemma-3-27b-it-Q4_K_M.gguf") != ModelName.qualifier("gemma-3-27b-it-Q8_0.gguf"))
    }

    @Test("The revision survives in the qualifier")
    func keepsRevision() {
        #expect(ModelName.qualifier("Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf").contains("2507"))
    }

    @Test("A name with no tail qualifies as empty, so no stray separator is shown")
    func emptyWhenNothingToSay() {
        #expect(ModelName.qualifier("Llama-3-8B.gguf") == "")
    }

    @Test("The bare format token alone is not a qualifier")
    func formatOnlyIsEmpty() {
        #expect(ModelName.qualifier("Mistral-7B-gguf.gguf") == "")
    }
}
