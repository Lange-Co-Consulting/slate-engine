import Foundation
import SlateCore

public struct ShellError: Error, Equatable { public let reason: String }

public struct ShellTool: Sendable {
    public let workspaceRoot: URL
    public let timeout: Duration
    public static let maxOutputBytes = 2_000_000
    public init(workspaceRoot: URL, timeout: Duration = .seconds(120)) {
        self.workspaceRoot = workspaceRoot
        self.timeout = timeout
    }

    public func run(_ command: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            if let reason = CommandBlocklist.match(command) {
                continuation.finish(throwing: ShellError(reason: reason)); return
            }
            let process = Process()
            let scratch: URL
            do { scratch = try WorkspaceSandbox.scratchDirectory() }
            catch {
                continuation.finish(throwing: ShellError(reason: "sandbox scratch setup failed: \(error.localizedDescription)"))
                return
            }
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
                try? FileManager.default.removeItem(at: scratch)
                continuation.finish(throwing: ShellError(reason: "macOS command sandbox is unavailable; refusing to run an unrestricted command"))
                return
            }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            // `-f` skips user/global shell startup files. An agent command must
            // not implicitly execute unrelated ~/.zshrc or login hooks.
            process.arguments = ["-p", WorkspaceSandbox.profile(workspace: workspaceRoot, scratch: scratch),
                                 "/bin/zsh", "-f", "-c", command]
            let scopedWorkspace = WorkspaceSandbox.physicalURL(workspaceRoot)
            process.currentDirectoryURL = scopedWorkspace
            var environment = WorkspaceSandbox.environment(scratch: scratch)
            // `Process` changes the current directory without populating PWD.
            // Supplying the already-scoped physical path keeps shell built-ins
            // deterministic and grants no additional filesystem access.
            environment["PWD"] = scopedWorkspace.path
            process.environment = environment
            let outputURL = scratch.appendingPathComponent("command-output.log")
            let outputHandle: FileHandle
            let tailer: ShellOutputTail
            do {
                // A sandboxed child cannot safely inherit Codex's anonymous
                // output pipe. Use a private, bounded-by-reader scratch file
                // instead; it stays inside the Seatbelt write scope and is
                // deleted as soon as the command finishes.
                try PrivateStorage.write(Data(), to: outputURL)
                outputHandle = try FileHandle(forWritingTo: outputURL)
                tailer = try ShellOutputTail(fileURL: outputURL, process: process, continuation: continuation)
            } catch {
                try? FileManager.default.removeItem(at: scratch)
                continuation.finish(throwing: ShellError(reason: "sandbox output setup failed: \(error.localizedDescription)"))
                return
            }
            process.standardOutput = outputHandle
            process.standardError = outputHandle
            process.standardInput = FileHandle.nullDevice
            let outputQueue = DispatchQueue(label: "com.langeundco.slate.shell-output")
            let outputTimer = DispatchSource.makeTimerSource(queue: outputQueue)
            outputTimer.schedule(deadline: .now(), repeating: .milliseconds(25))
            outputTimer.setEventHandler { tailer.drain() }
            outputTimer.resume()

            func finishOutput() {
                try? outputHandle.close()
                outputTimer.cancel()
                outputQueue.sync { tailer.drain() }
            }

            let driver = Task {
                defer { try? FileManager.default.removeItem(at: scratch) }
                do {
                    let status: Int32 = try await withTaskCancellationHandler {
                        try await withThrowingTaskGroup(of: Int32.self) { group in
                            group.addTask { try await Self.runAndWait(process) }
                            group.addTask {
                                try await Task.sleep(for: timeout)
                                if process.isRunning { process.terminate() }
                                return -1
                            }
                            let first = try await group.next()!
                            group.cancelAll()
                            return first
                        }
                    } onCancel: { if process.isRunning { process.terminate() } }
                    finishOutput()
                    if tailer.isTruncated {
                        continuation.finish(throwing: ShellError(reason: "output exceeded \(Self.maxOutputBytes) bytes"))
                    } else if status == -1 {
                        continuation.finish(throwing: ShellError(reason: "timed out"))
                    } else if status != 0 {
                        // A non-zero exit is NOT an error for an agent - it is the
                        // signal it most needs to see (a failing build/test, `grep`
                        // with no match). Keep the streamed output and append the
                        // exit code, then finish normally; throwing here would make
                        // the tool consumer discard all captured output and the
                        // model would self-correct blind.
                        continuation.yield("\n[exit status \(status)]")
                        continuation.finish()
                    } else { continuation.finish() }
                } catch {
                    if process.isRunning { process.terminate() }
                    finishOutput()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in driver.cancel() }
        }
    }

    private static func runAndWait(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
            do { try process.run() } catch { cont.resume(throwing: ShellError(reason: "spawn failed: \(error)")) }
        }
    }
}

final class ShellBox<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

/// Tails the sandbox's private output file on one serial queue. Keeping this
/// separate from the child process avoids granting a Seatbelted shell access
/// to the host application's anonymous pipes.
private final class ShellOutputTail: @unchecked Sendable {
    private let reader: FileHandle
    private let process: Process
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private var partial = Data()
    private var outputBytes = 0
    private(set) var isTruncated = false

    init(fileURL: URL, process: Process, continuation: AsyncThrowingStream<String, Error>.Continuation) throws {
        reader = try FileHandle(forReadingFrom: fileURL)
        self.process = process
        self.continuation = continuation
    }

    deinit { try? reader.close() }

    func drain() {
        guard !isTruncated else { return }
        while let data = try? reader.read(upToCount: 64 * 1_024), !data.isEmpty {
            outputBytes += data.count
            if outputBytes > ShellTool.maxOutputBytes {
                isTruncated = true
                if process.isRunning { process.terminate() }
                continuation.yield("\n[output limit reached; command terminated]\n")
                return
            }
            emit(data)
        }
    }

    private func emit(_ data: Data) {
        var bytes = partial + data
        if let text = String(data: bytes, encoding: .utf8) {
            partial = Data()
            if !text.isEmpty { continuation.yield(text) }
            return
        }
        while !bytes.isEmpty, String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        if let text = String(data: bytes, encoding: .utf8), !text.isEmpty { continuation.yield(text) }
        partial = data.suffix(data.count - bytes.count)
    }
}
