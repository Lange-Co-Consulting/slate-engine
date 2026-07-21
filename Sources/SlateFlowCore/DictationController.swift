import Foundation
import Observation

/// The dictation state machine (spec items 1, 2, 5, 6). ALL side effects are
/// injected via `Deps`, so every path is unit-tested with fakes; `FlowRuntime`
/// in the app wires the real tap/audio/STT/LLM/inserter.
///
/// Interaction contract (Wispr Flow semantics):
///   • Fn down starts recording immediately (no latency waiting to classify).
///   • Release after ≥0.3 s = push-to-talk → finalize.
///   • Release before 0.3 s = a tap: a lone tap discards the blip; a second tap
///     within 0.4 s flips into hands-free (recording keeps running).
///   • While hands-free, any completed tap finalizes. Esc cancels. `tick()`
///     enforces the 20-minute cap.
@MainActor @Observable
public final class DictationController {
    public enum State: Equatable, Sendable { case idle, recording, processing, inserting }

    public struct Deps {
        public var startCapture: () -> Void
        public var stopCapture: () -> [Float]
        public var transcribe: ([Float], String?) async throws -> String
        /// (rawText, frontmostBundleID) → polished text. M2 wires the LLM.
        public var cleanup: (String, String?) async -> String
        public var insert: (String) async -> Bool
        public var now: () -> Double
        public init(startCapture: @escaping () -> Void,
                    stopCapture: @escaping () -> [Float],
                    transcribe: @escaping ([Float], String?) async throws -> String,
                    cleanup: @escaping (String, String?) async -> String,
                    insert: @escaping (String) async -> Bool,
                    now: @escaping () -> Double) {
            self.startCapture = startCapture; self.stopCapture = stopCapture
            self.transcribe = transcribe; self.cleanup = cleanup
            self.insert = insert; self.now = now
        }
    }

    public private(set) var state: State = .idle
    public private(set) var handsFree = false
    public var lastError: String?
    /// BCP-47 language override ("de"/"en"); nil = auto-detect.
    public var language: String?
    /// Off = raw mode: the transcript pastes without the cleanup pass.
    public var smartFormatting = true
    /// Hands-free/PTT session cap (spec item 2).
    public var maxSessionSeconds: Double = 20 * 60

    private let deps: Deps
    private var downAt = 0.0
    private var lastTapUpAt = -10.0
    private var inflight: Task<Void, Never>?
    private let holdThreshold = 0.3
    private let doubleTapWindow = 0.4

    public init(deps: Deps) { self.deps = deps }

    public func fnEdge(_ edge: FnDebouncer.Edge) {
        switch edge {
        case .down:
            downAt = deps.now()
            if state == .idle { begin() }
        case .up:
            let now = deps.now()
            let held = now - downAt
            guard state == .recording else { return }
            if handsFree {
                handsFree = false                     // any completed tap stops hands-free
                finish()
            } else if held >= holdThreshold {
                finish()                              // push-to-talk release
            } else {                                  // short tap
                if downAt - lastTapUpAt <= doubleTapWindow {
                    handsFree = true                  // double-tap: keep recording
                } else {
                    abortRecording()                  // lone blip: discard
                }
                lastTapUpAt = now
            }
        }
    }

    /// Click-to-talk (composer mic button): first call starts a hands-free
    /// style session, the next call finalizes it. Reuses the exact PTT
    /// pipeline (transcribe → cleanup → insert), so behavior stays identical.
    public func toggleManual() {
        if state == .idle {
            downAt = deps.now()
            handsFree = true
            begin()
        } else if state == .recording {
            handsFree = false
            finish()
        }
    }

    /// Esc: throw the current recording away.
    public func cancel() {
        guard state == .recording else { return }
        handsFree = false
        abortRecording()
    }

    /// Session-cap enforcement - FlowRuntime calls this on a timer while recording.
    public func tick() {
        if state == .recording, deps.now() - downAt >= maxSessionSeconds {
            handsFree = false
            finish()
        }
    }

    private func begin() {
        lastError = nil
        state = .recording
        deps.startCapture()
    }

    private func abortRecording() {
        _ = deps.stopCapture()
        state = .idle
    }

    private func finish() {
        guard state == .recording else { return }
        let samples = deps.stopCapture()
        state = .processing
        let lang = language
        let smart = smartFormatting
        inflight = Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await deps.transcribe(samples, lang)
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { state = .idle; return }
                let polished = smart ? await deps.cleanup(text, nil) : text
                state = .inserting
                let ok = await deps.insert(polished)
                if !ok { lastError = "Couldn't insert - the text is on your clipboard." }
            } catch {
                lastError = "Transcription failed."
            }
            state = .idle
        }
    }

    /// Await the in-flight transcribe→cleanup→insert pipeline (tests + shutdown).
    public func settle() async { await inflight?.value }
}
