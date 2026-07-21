# slate-engine

The open-source local-AI engine behind **[Slate](https://slate-app.org)** - a
native macOS workspace that runs open models entirely on your Mac.

Everything here runs **100% offline**. No account, no telemetry, no cloud calls.
This is the engine; the polished Slate app (and its optional one-time Pro layer)
is built on top of it.

## What's in here

| Module | What it does |
| --- | --- |
| `SlateCore` | The heart: tool registry + agent loop, the **multi-model Roundtable** orchestration, conversation memory + per-project memory, repo map, checkpoints, sandbox policy, command bl\*list, private on-disk storage. Pure Swift, no I/O side effects beyond files you point it at. |
| `SlateLlama` | Local LLM inference over **llama.cpp** (GGUF), with a prompt/KV cache and the agent factory that wires the tools. |
| `SlateDiffusion` | Local image generation over **stable-diffusion.cpp**. |
| `SlateSTT` | On-device speech-to-text (NVIDIA Parakeet via FluidAudio) + the dictation state machine. |
| `SlateFlowCore` / `SlateFlowCleanup` | Dictation flow + LLM transcript cleanup. |
| `slatectl` | A headless CLI over the engine: run a local agent from your terminal. |

## Why it's open

Slate's pitch is "your work stays on your Mac." The honest way to back that claim
is to let you read the engine and verify it, with no hidden network calls, no
telemetry. Fork it, build on it, or embed it.

## Requirements

- macOS 26+, Apple silicon
- Swift 6 toolchain

The `llama` and `stable-diffusion` binary frameworks are hosted as
[release assets](../../releases) (kept out of git); SwiftPM fetches them on build.

## Use it

```swift
.package(url: "https://github.com/Lange-Co-Consulting/slate-engine.git", from: "0.1.1")
```

```sh
swift build
swift run slatectl --help
```

## License

MIT - see [LICENSE](LICENSE). Built by [Lange und Co. Consulting GmbH](https://slate-app.org)
Third-party components (llama.cpp, stable-diffusion.cpp, FluidAudio, ripgrep) keep
their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
