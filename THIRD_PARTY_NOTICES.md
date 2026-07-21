# Third-party notices

slate-engine is MIT-licensed. It builds on the following components, each under
its own license:

| Component | Where | License |
| --- | --- | --- |
| llama.cpp | `llama.xcframework` (release asset) | MIT |
| stable-diffusion.cpp | `sd.xcframework` (release asset) | MIT |
| FluidAudio (Parakeet ASR, Silero VAD) | SwiftPM dependency | Apache-2.0 |
| fastcluster (via FluidAudio) | transitive | BSD-3-Clause |
| VBx (via FluidAudio) | transitive | Apache-2.0 |
| ripgrep | invoked as a binary for content search | MIT OR Unlicense |
| PCRE2 (via ripgrep) | transitive | BSD-3-Clause WITH PCRE2-exception |

Model weights are never bundled. Any model is downloaded or imported by the user
and remains subject to its own provider's license.
