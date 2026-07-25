import Foundation
import llama
import SlateCore

// Run llama.cpp's backend registration exactly once per process (thread-safe
// lazy global init). Registers the Metal backend so GPU offload works.
private let llamaBackendInit: Void = {
    ggml_backend_load_all()
}()

private extension Array where Element == String {
    /// Calls `body` with a mutable `char **` buffer (base pointer + count) valid
    /// for its duration. The C grammar init copies the patterns internally, so the
    /// strdup'd strings are freed when this returns.
    func withCStringArray<R>(_ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?, Int) throws -> R) rethrows -> R {
        let dups = map { strdup($0) }                       // [UnsafeMutablePointer<CChar>?]
        defer { dups.forEach { free($0) } }
        var ptrs: [UnsafePointer<CChar>?] = dups.map { $0.map { UnsafePointer($0) } }
        return try ptrs.withUnsafeMutableBufferPointer { buf in
            try body(buf.baseAddress, buf.count)
        }
    }
}

/// Thread-safe boolean for cooperative cancellation of the C generation loop.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    func clear() { lock.withLock { flag = false } }
    var isSet: Bool { lock.withLock { flag } }
}

/// Turns gpt-oss / OpenAI-harmony channel output into text Slate's reasoning UI
/// understands: the `analysis`/`commentary` channels become a collapsed
/// `<think>…</think>` block; the `final` channel becomes the visible answer.
///
/// The model streams the FULL harmony structure as literal text - llama.cpp tags
/// `<|channel|>` `<|message|>` `<|start|>` `<|end|>` as user-defined so they
/// render as text regardless of the `special` flag (only `<|return|>`/`<|call|>`
/// are EOG and never reach us). So we parse those markers directly.
///
/// Emission is append-only BY CONSTRUCTION: we keep two monotonic buffers
/// (analysis, final) parsed from the raw-so-far and emit only each buffer's
/// newly-confirmed suffix. We never diff a re-rendered whole string - the old
/// version did, and when the analysis→final transition consumed the already-
/// emitted `final` label and inserted `</think>`, the diff stopped being a
/// prefix-extension and silently dropped the entire answer.
final class HarmonyThink {
    let active: Bool
    private var raw = ""
    private var sentAnalysis = 0
    private var sentFinal = 0
    private var thinkOpened = false
    private var thinkClosed = false
    init(active: Bool) { self.active = active }

    func feed(_ piece: String) -> [String] {
        guard active else { return [piece] }
        raw += piece
        return emit(closing: false)
    }
    func finish() -> [String] {
        guard active else { return [] }
        return emit(closing: true)
    }

    /// Convenience one-shot (tests / non-streaming): parse a complete raw string
    /// into the `<think>…</think>answer` display form. No trimming here - it must
    /// equal the streamed concatenation exactly (the display layer trims think
    /// content itself in Reasoning.split).
    static func render(_ raw: String) -> String {
        let p = parse(raw, closing: true)
        var s = ""
        if p.sawAnalysis { s += "<think>\n" + p.analysis + "\n</think>\n\n" }
        if p.sawFinal { s += p.final }
        else if !p.sawAnalysis { s += p.fallback }   // no channels at all → plain answer
        return s
    }

    private func emit(closing: Bool) -> [String] {
        let p = Self.parse(raw, closing: closing)
        var out: [String] = []
        // Analysis (+ commentary) → collapsed reasoning.
        if p.sawAnalysis {
            if !thinkOpened { thinkOpened = true; out.append("<think>\n") }
            if !thinkClosed { out += forward(p.analysis, &sentAnalysis) }
        }
        // Final channel → visible answer. Close the think block exactly once first.
        if p.sawFinal {
            if !thinkClosed { thinkClosed = true; if thinkOpened { out.append("\n</think>\n\n") } }
            out += forward(p.final, &sentFinal)
        } else if closing {
            if !p.sawAnalysis {
                // Defensive: markerless output - surface it rather than black-holing it.
                out += forward(p.fallback, &sentFinal)
            } else if thinkOpened, !thinkClosed {
                // Truncated mid-analysis (stop/context-full): close the block so
                // the stored message matches render() and never dangles open.
                thinkClosed = true
                out.append("\n</think>\n\n")
            }
        }
        return out.filter { !$0.isEmpty }
    }

    /// Emit only the chars of `buf` beyond what we've already sent (append-only).
    private func forward(_ buf: String, _ sent: inout Int) -> [String] {
        let chars = Array(buf)
        guard chars.count > sent else { return [] }
        let d = String(chars[sent...]); sent = chars.count
        return [d]
    }

    struct Parsed { var analysis = ""; var final = ""; var fallback = ""; var sawAnalysis = false; var sawFinal = false }

    /// Walk `<|channel|>NAME<|message|>BODY` segments out of the raw stream. BODY
    /// runs to the next structural marker (or end). While a body is still growing
    /// (no following marker yet) and we're not closing, a partial trailing marker
    /// is held back so a half-arrived `<|end|>` never flashes as content.
    static func parse(_ raw: String, closing: Bool) -> Parsed {
        var out = Parsed()
        let stops = ["<|end|>", "<|start|>", "<|channel|>", "<|return|>", "<|call|>"]
        var from = raw.startIndex
        while let msg = raw.range(of: "<|message|>", range: from..<raw.endIndex) {
            // Channel name: text after the last <|channel|> before this <|message|>.
            let head = raw[from..<msg.lowerBound]
            var name = head.range(of: "<|channel|>", options: .backwards).map { String(head[$0.upperBound...]) } ?? String(head)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let cut = name.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "<" }) {
                name = String(name[..<cut])   // "commentary to=functions…" → "commentary"
            }
            // Body: from after <|message|> to the nearest following structural marker.
            let bodyStart = msg.upperBound
            var bodyEnd = raw.endIndex
            var bounded = false
            for stop in stops {
                if let r = raw.range(of: stop, range: bodyStart..<raw.endIndex), r.lowerBound < bodyEnd {
                    bodyEnd = r.lowerBound; bounded = true
                }
            }
            var body = String(raw[bodyStart..<bodyEnd])
            if !bounded && !closing { body = holdbackPartialMarker(body) }
            if name.hasPrefix("final") {
                out.sawFinal = true; out.final += body
            } else if name.hasPrefix("analysis") || name.hasPrefix("commentary")
                        || name.hasPrefix("thinking") || name.hasPrefix("thought") {
                out.sawAnalysis = true; out.analysis += body
            }   // unknown channel → ignore (never leak)
            from = bodyEnd
        }
        if !out.sawAnalysis && !out.sawFinal && !raw.contains("<|channel|>") {
            out.fallback = closing ? raw : holdbackPartialMarker(raw)
        }
        return out
    }

    /// Drop a trailing run that could be the start of a control marker ("<", "<|",
    /// "<|mess", "<|end|"…) so a half-arrived marker never leaks. Real content
    /// like "a < b" or "<div>" is untouched - only a "<|"-style marker prefix is
    /// held. The trailing `\|?` matters: a marker split one char before its
    /// closing '>' ("<|end|") must be held too, else the fragment is emitted and
    /// the monotonic `sent` counter can never walk it back.
    static func holdbackPartialMarker(_ s: String) -> String {
        guard let lt = s.range(of: "<", options: .backwards) else { return s }
        let tail = String(s[lt.lowerBound...])
        if tail.range(of: #"^<(\|[A-Za-z_]*\|?)?$"#, options: .regularExpression) != nil {
            return String(s[..<lt.lowerBound])
        }
        return s
    }
}

public actor LlamaEngine: LLMEngine {
    // C handles are immutable after init and freed exactly once in deinit.
    // `nonisolated(unsafe)` lets the nonisolated deinit free them under Swift 6
    // strict concurrency; all *use* stays inside this actor's serial executor.
    private nonisolated(unsafe) let model: OpaquePointer
    private nonisolated(unsafe) let vocab: OpaquePointer
    private nonisolated(unsafe) let ctx: OpaquePointer
    /// Multimodal projector context - non-nil only when an mmproj GGUF was supplied
    /// and loaded. All mtmd_* use stays on this actor's serial executor.
    private nonisolated(unsafe) let mtmd: OpaquePointer?
    private let nCtx: Int32
    /// Max tokens per llama_decode call (mirrors cparams.n_batch) - prompts are
    /// prefilled in chunks of this size.
    private let nBatchCap: Int32
    /// The context window actually in use, and the model's trained maximum (from GGUF
    /// metadata) - surfaced so the UI can show real numbers, not a hardcoded cap.
    public nonisolated let contextWindow: Int
    public nonisolated let trainedContext: Int
    /// How many multi-token-prediction heads the loaded weights carry, 0 for none.
    ///
    /// Reported, not used. A model with MTP heads can in principle draft its own next tokens and
    /// verify them in a single pass, which is speculative decoding without a second model in
    /// memory. The runtime supports it, but of that machinery only this one accessor is declared
    /// `LLAMA_API` in the pinned header; the functions that would *execute* the heads are
    /// C++-mangled and undeclared. Driving them would mean hand-declaring mangled symbols against
    /// a SHA-pinned binary, which is a rebuild of the framework rather than a feature.
    ///
    /// Surfacing the count is honest and free: it says what the weights can do without implying
    /// Slate does it.
    public nonisolated let mtpHeads: Int
    /// Cooperative stop flag, set from any thread (Stop button) and polled by the
    /// generation loop. More reliable than Task cancellation, which doesn't fire
    /// through `for try await` while the producer is actively yielding tokens.
    private let stopFlag = StopFlag()
    /// Tokens currently materialized in the KV cache (fed prompt + generated),
    /// tracked across calls so the next turn only decodes the divergent suffix
    /// instead of re-prefilling the whole templated history (PromptCache).
    private var kvTokens: [llama_token] = []

    /// True when a vision projector is attached, so image input is supported.
    public nonisolated var isVision: Bool { mtmd != nil }
    public nonisolated func requestStop() { stopFlag.set() }
    public nonisolated func clearStop() { stopFlag.clear() }

    public init(modelPath: String, mmprojPath: String? = nil, nCtx: UInt32 = 8192, nGpuLayers: Int32 = 999) throws {
        _ = llamaBackendInit

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = nGpuLayers
        guard let model = llama_model_load_from_file(modelPath, mparams) else {
            throw GenerationError.modelLoadFailed
        }
        guard let vocab = llama_model_get_vocab(model) else {
            llama_model_free(model)
            throw GenerationError.modelLoadFailed
        }
        // Clamp the requested window to what the model was trained for.
        let trained = Int(llama_model_n_ctx_train(model))
        let effective = trained > 0 ? min(Int(nCtx), trained) : Int(nCtx)
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(effective)
        let batchCap = min(effective, 2048)              // cap batch so big windows don't blow the compute buffer
        cparams.n_batch = UInt32(batchCap)
        guard let ctx = llama_init_from_model(model, cparams) else {
            llama_model_free(model)
            throw GenerationError.contextCreationFailed
        }
        self.model = model
        self.vocab = vocab
        self.ctx = ctx
        self.nCtx = Int32(effective)
        self.nBatchCap = Int32(batchCap)
        self.contextWindow = effective
        self.trainedContext = trained
        self.mtpHeads = max(0, Int(llama_model_n_layer_nextn(model)))

        // Optional multimodal projector. A failure here is non-fatal: the model
        // still works as a text engine, so we fall back to nil rather than throw.
        if let mmprojPath {
            var p = mtmd_context_params_default()    // never zero-init: defaults set the media marker
            p.use_gpu = true
            p.print_timings = false
            self.mtmd = mmprojPath.withCString { mtmd_init_from_file($0, model, p) }
        } else {
            self.mtmd = nil
        }
    }

    deinit {
        if let mtmd { mtmd_free(mtmd) }
        llama_free(ctx)
        llama_model_free(model)
        // Do NOT call llama_backend_free per-engine (process-global).
    }

    public func generate(messages: [ChatMessage], grammar: GrammarSpec?, options: GenOptions) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try self.runGeneration(messages: messages, grammar: grammar, options: options) { piece in
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Actor-isolated generation (single-threaded C section)

    private func runGeneration(messages: [ChatMessage],
                               grammar: GrammarSpec?,
                               options: GenOptions,
                               onPiece rawEmit: @escaping (String) -> Void) throws {
        // gpt-oss / harmony models stream the full channel structure as text
        // (<|channel|>analysis<|message|>… <|end|> <|start|>assistant<|channel|>
        // final<|message|>…). HarmonyThink parses those channels: analysis →
        // collapsed <think>…</think>, final → the visible answer. Only in free
        // chat - a grammar means constrained tool-calling, no reasoning.
        let think = HarmonyThink(active: grammar == nil && isHarmonyReasoning())
        let onPiece: (String) -> Void = { piece in think.feed(piece).forEach(rawEmit) }
        defer { think.finish().forEach(rawEmit) }

        // Vision path: a projector is attached and at least one turn carries an image.
        // mtmd prefills at n_past=0, so it needs a clean cache; reuse is text-only.
        if let mtmd, messages.contains(where: { $0.imagePath != nil }) {
            llama_memory_clear(llama_get_memory(ctx), true)
            kvTokens = []
            try runVisionGeneration(messages: messages, mtmd: mtmd, grammar: grammar, options: options, onPiece: onPiece)
            return
        }

        let prompt = applyChatTemplate(messages)

        // Tokenize: two-pass negative-length idiom.
        let nPrompt: Int32 = prompt.withCString { c in
            -llama_tokenize(vocab, c, Int32(strlen(c)), nil, 0, true, true)
        }
        guard nPrompt > 0 else { throw GenerationError.tokenizationFailed }
        var tokens = [llama_token](repeating: 0, count: Int(nPrompt))
        let written: Int32 = prompt.withCString { c in
            tokens.withUnsafeMutableBufferPointer { buf in
                llama_tokenize(vocab, c, Int32(strlen(c)), buf.baseAddress, nPrompt, true, true)
            }
        }
        guard written >= 0 else { throw GenerationError.tokenizationFailed }

        // Sampler chain: [grammar first] -> min_p -> temp -> dist (terminal selector mandatory).
        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(smpl) } // frees added sub-samplers too
        if let grammar {
            let g: UnsafeMutablePointer<llama_sampler>?
            if grammar.triggerPatterns.isEmpty {
                g = llama_sampler_init_grammar(vocab, grammar.gbnf, grammar.root)
            } else {
                g = grammar.triggerPatterns.withCStringArray { ptr, count in
                    llama_sampler_init_grammar_lazy_patterns(
                        vocab, grammar.gbnf, grammar.root, ptr, count, nil, 0)
                }
            }
            guard let g else { throw GenerationError.grammarParseFailed }
            llama_sampler_chain_add(smpl, g)
        }
        llama_sampler_chain_add(smpl, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(Float(max(0.01, options.temperature))))
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))

        guard tokens.count < Int(nCtx) else {
            throw GenerationError.executionFailedText(
                "The prompt (≈\(tokens.count) tokens) exceeds the context window (\(nCtx)). Shorten the conversation or raise the window in Settings.")
        }

        // KV prefix reuse: keep the longest common prefix with what's already in
        // the cache, drop only the divergent tail, and feed only the suffix.
        // Turn 2..n of a conversation (and every agent-loop iteration) then pays
        // for the delta instead of the whole templated history.
        let mem = llama_get_memory(ctx)
        var plan = PromptCache.plan(previous: kvTokens, next: tokens)   // llama_token == Int32
        if plan.keep > 0 {
            // Recurrent/hybrid models (Mamba/RWKV/Gated-DeltaNet MoEs) cannot roll
            // back state: a partial seq_rm returns false and removes NOTHING. Fall
            // back to a full re-prefill or kvTokens would diverge from real KV state.
            if !llama_memory_seq_rm(mem, 0, llama_pos(plan.keep), -1) {
                llama_memory_clear(mem, true)
                plan = PromptCache.plan(previous: [], next: tokens)
            }
        } else {
            llama_memory_clear(mem, true)
        }
        kvTokens = Array(tokens[..<plan.keep])

        // Chunked prefill of the suffix - never more than n_batch per decode
        // (a single oversized batch is rejected by llama_decode). Chunks are kept
        // SMALL so the Stop button reacts within ~a second even during the long
        // prompt-processing phase of a big model (llama_decode itself can't be
        // interrupted; the flag is only checked between chunks).
        let step = Swift.min(Int(nBatchCap), 512)
        var idx = plan.feed.lowerBound
        while idx < plan.feed.upperBound {
            if stopFlag.isSet { return }         // stopped before sampling: no stale-logit sample
            try Task.checkCancellation()
            let end = Swift.min(idx + step, plan.feed.upperBound)
            var rc: Int32 = 0
            tokens.withUnsafeMutableBufferPointer { buf in
                let batch = llama_batch_get_one(buf.baseAddress! + idx, Int32(end - idx))
                rc = llama_decode(ctx, batch)
            }
            guard rc == 0 else {
                kvTokens = []; llama_memory_clear(mem, true)   // unknown KV state → resync
                throw GenerationError.decodeFailed(rc)
            }
            kvTokens.append(contentsOf: tokens[idx..<end])
            idx = end
        }

        // Generation: the prefill left fresh logits, so sample first, then decode
        // the accepted token (single-token batch auto-positions after the prefix).
        var utf8 = [UInt8]() // buffer to join multi-byte codepoints split across tokens
        var generated = 0
        while generated < options.maxTokens {
            if stopFlag.isSet { break }          // Stop button
            try Task.checkCancellation() // cooperative stop between decodes

            var id = llama_sampler_sample(smpl, ctx, -1) // applies chain + accepts
            if llama_vocab_is_eog(vocab, id) { break }

            var buf = [CChar](repeating: 0, count: 256)
            let n = llama_token_to_piece(vocab, id, &buf, 256, 0, true)
            if n < 0 { throw GenerationError.decodeFailed(n) }
            buf.withUnsafeBufferPointer { p in
                for i in 0..<Int(n) { utf8.append(UInt8(bitPattern: p[i])) }
            }
            if let s = String(bytes: utf8, encoding: .utf8) {
                onPiece(s)
                utf8.removeAll(keepingCapacity: true)
            }
            generated += 1

            let used = llama_memory_seq_pos_max(mem, 0) + 1
            if used + 1 > nCtx { break } // context full
            let rc = withUnsafeMutablePointer(to: &id) {
                llama_decode(ctx, llama_batch_get_one($0, 1))
            }
            guard rc == 0 else {
                kvTokens = []; llama_memory_clear(mem, true)
                throw GenerationError.decodeFailed(rc)
            }
            kvTokens.append(id)
        }
        // Flush any trailing bytes of a glyph left incomplete at loop exit
        // (U+FFFD substitution) rather than silently dropping it.
        if !utf8.isEmpty { onPiece(String(decoding: utf8, as: UTF8.self)) }
    }

    // MARK: - Multimodal generation (mtmd: image -> embeddings -> decode -> text)

    /// Prefills the context with text + image(s) via mtmd, then runs the shared
    /// token loop. Mirrors the full-reprefill behaviour of the text path: every
    /// turn re-encodes the whole templated history (markers injected) + bitmaps.
    private func runVisionGeneration(messages: [ChatMessage],
                                     mtmd: OpaquePointer,
                                     grammar: GrammarSpec?,
                                     options: GenOptions,
                                     onPiece: (String) -> Void) throws {
        let marker = String(cString: mtmd_default_marker())   // "<__media__>"

        // Load each image and inject a marker ONLY for ones that read successfully,
        // so the marker count always matches the bitmap count. A moved/deleted image
        // (e.g. on regenerate over old history) degrades that turn to text instead of
        // aborting it. Bitmaps are freed after tokenize copies what it needs.
        var bitmaps: [OpaquePointer?] = []
        defer { for b in bitmaps { if let b { mtmd_bitmap_free(b) } } }
        var withMarkers: [ChatMessage] = []
        for m in messages {
            guard let path = m.imagePath else { withMarkers.append(m); continue }
            let w = path.withCString { mtmd_helper_bitmap_init_from_file(mtmd, $0, false) }
            if let bmp = w.bitmap {
                bitmaps.append(bmp)
                withMarkers.append(ChatMessage(role: m.role, content: marker + "\n" + m.content))
            } else {
                withMarkers.append(m)   // unreadable image - text-only for this turn
            }
        }
        let prompt = applyChatTemplate(withMarkers)

        let chunks = mtmd_input_chunks_init()
        defer { mtmd_input_chunks_free(chunks) }

        var trc: Int32 = -1
        prompt.withCString { cprompt in
            var it = mtmd_input_text(text: cprompt, add_special: true, parse_special: true)
            bitmaps.withUnsafeMutableBufferPointer { buf in
                trc = mtmd_tokenize(mtmd, chunks, &it, buf.baseAddress, buf.count)
            }
        }
        // 0 ok; 1 = marker/bitmap count mismatch; 2 = image preprocess error.
        guard trc == 0 else { throw GenerationError.executionFailedText("Image tokenize failed (code \(trc)).") }

        // One call: clip-encode image chunks -> embeddings -> llama_decode, plus
        // decode text chunks. logits_last=true leaves the final logits ready to sample.
        // The KV cache was cleared in runGeneration, so prefilling at n_past=0 is correct.
        var nPast: llama_pos = 0
        // The 6th argument is n_batch - must respect the context's real batch cap,
        // or a >2048-token text chunk aborts inside llama_decode (GGML_ASSERT).
        let erc = mtmd_helper_eval_chunks(mtmd, ctx, chunks, 0, 0, nBatchCap, true, &nPast)
        guard erc == 0 else { throw GenerationError.decodeFailed(erc) }

        // Sampler chain: [grammar first] -> min_p -> temp -> dist, mirroring the text path.
        let smpl = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(smpl) }
        if let grammar {
            let g: UnsafeMutablePointer<llama_sampler>?
            if grammar.triggerPatterns.isEmpty {
                g = llama_sampler_init_grammar(vocab, grammar.gbnf, grammar.root)
            } else {
                g = grammar.triggerPatterns.withCStringArray { ptr, count in
                    llama_sampler_init_grammar_lazy_patterns(
                        vocab, grammar.gbnf, grammar.root, ptr, count, nil, 0)
                }
            }
            guard let g else { throw GenerationError.grammarParseFailed }
            llama_sampler_chain_add(smpl, g)
        }
        llama_sampler_chain_add(smpl, llama_sampler_init_min_p(0.05, 1))
        llama_sampler_chain_add(smpl, llama_sampler_init_temp(Float(max(0.01, options.temperature))))
        llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED))

        // Generation loop. The prefill already decoded, so we sample first, then
        // decode each accepted token (single-token batch auto-positions after nPast).
        var utf8 = [UInt8]()
        var generated = 0
        while generated < options.maxTokens {
            if stopFlag.isSet { break }          // Stop button
            try Task.checkCancellation()

            var id = llama_sampler_sample(smpl, ctx, -1)
            if llama_vocab_is_eog(vocab, id) { break }

            var buf = [CChar](repeating: 0, count: 256)
            let n = llama_token_to_piece(vocab, id, &buf, 256, 0, true)
            if n < 0 { throw GenerationError.decodeFailed(n) }
            buf.withUnsafeBufferPointer { p in
                for i in 0..<Int(n) { utf8.append(UInt8(bitPattern: p[i])) }
            }
            if let s = String(bytes: utf8, encoding: .utf8) {
                onPiece(s)
                utf8.removeAll(keepingCapacity: true)
            }
            generated += 1

            let used = llama_memory_seq_pos_max(llama_get_memory(ctx), 0) + 1
            if used + 1 > nCtx { break }   // context full
            let batch = withUnsafeMutablePointer(to: &id) { llama_batch_get_one($0, 1) }
            let rc = llama_decode(ctx, batch)
            if rc != 0 { throw GenerationError.decodeFailed(rc) }
        }
        if !utf8.isEmpty { onPiece(String(decoding: utf8, as: UTF8.self)) }
    }

    /// True if the model's chat template is OpenAI-harmony (gpt-oss): it renders
    /// hidden reasoning in an `analysis`/`final` channel structure.
    private func isHarmonyReasoning() -> Bool {
        guard let t = llama_model_chat_template(model, nil) else { return false }
        let s = String(cString: t)
        return s.contains("<|channel|>") || (s.contains("channel") && s.contains("analysis"))
    }

    /// Renders messages using the model's built-in chat template.
    private func applyChatTemplate(_ messages: [ChatMessage]) -> String {
        let tmpl = llama_model_chat_template(model, nil) // nil = default; may be nil

        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        var cmsgs: [llama_chat_message] = messages.map { m in
            let r = strdup(m.role.rawValue)!
            let c = strdup(m.content)!
            owned.append(r); owned.append(c)
            return llama_chat_message(role: UnsafePointer(r), content: UnsafePointer(c))
        }

        // First pass: required length (buf = nil, length = 0).
        let needed = llama_chat_apply_template(tmpl, &cmsgs, cmsgs.count, true, nil, 0)
        guard needed > 0 else {
            // Fallback if the model has no usable template.
            return messages.map { "\($0.role.rawValue): \($0.content)" }
                .joined(separator: "\n") + "\nassistant:"
        }
        var out = [CChar](repeating: 0, count: Int(needed) + 1)
        let w = llama_chat_apply_template(tmpl, &cmsgs, cmsgs.count, true, &out, Int32(out.count))
        guard w > 0 else { return "" }
        let bytes = out.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
