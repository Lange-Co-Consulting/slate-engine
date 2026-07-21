import Testing
@testable import SlateCore

@Test func stripsQuantFormatAndFineTuneNoise() {
    #expect(ModelName.pretty("gemma-2-2b-it-Q4_K_M.gguf") == "Gemma 2 2B")
    #expect(ModelName.pretty("Qwen2.5-3B-Instruct-Q4_K_M.gguf") == "Qwen2.5 3B")
    #expect(ModelName.pretty("Llama-3.2-3B-Instruct-Q4_K_M.gguf") == "Llama 3.2 3B")
    #expect(ModelName.pretty("Phi-3.5-mini-instruct-Q4_K_M.gguf") == "Phi 3.5 mini")
}

@Test func dropsAbliteratedUncensoredAndUploaderTail() {
    #expect(ModelName.pretty("Gemma-4-12b-abliterated-gguf-Q4_K_M.gguf") == "Gemma 4 12B")
    #expect(ModelName.pretty("Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ3_M.gguf") == "Qwen3.6 27B")
}

@Test func keepsMeaningfulSecondaryTokens() {
    #expect(ModelName.pretty("Qwen3-Coder-30B-A3B-Instruct-UD-Q2_K_XL.gguf") == "Qwen3 Coder 30B A3B")
    #expect(ModelName.pretty("Mistral-7B-Instruct-v0.3.Q4_K_M.gguf") == "Mistral 7B")
}

@Test func normalizesParameterSizeCasing() {
    #expect(ModelName.pretty("MyModel-270m-Q4_K_M.gguf") == "MyModel 270M")
    #expect(ModelName.pretty("Foo-7b.gguf") == "Foo 7B")
}

@Test func survivesNamesWithNoNoise() {
    #expect(ModelName.pretty("CustomModel-13B") == "CustomModel 13B")
}

@Test func neverReturnsEmptyOnAllNoise() {
    #expect(!ModelName.pretty("Q4_K_M.gguf").isEmpty)
    #expect(!ModelName.pretty("gguf").isEmpty)
}
