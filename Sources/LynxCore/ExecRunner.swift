import Foundation
import Dispatch
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// 基于 Foundation.Process 的异步执行器（无 PTY，二进制安全）。
/// 用于 ControlMaster 复用通道上的监控采集、文件传输、Docker 操作等。
///
/// 读取策略：专用线程阻塞读至 EOF，而非 readabilityHandler ——
/// 后者在 corelibs-foundation (Linux) 上子进程退出时会丢失 EOF 事件。
/// spawn 后立即关闭父进程持有的管道副本，保证 EOF 语义在 macOS/Linux 一致。
public enum ExecRunner {

    // MARK: - 普通执行

    public static func run(executable: String,
                           arguments: [String] = [],
                           stdin: Data? = nil,
                           timeout: TimeInterval = 30,
                           environment: [String: String]? = nil,
                           currentDirectory: String? = nil) async throws -> ExecResult {
        let state = RunState()
        let process = state.process
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            process.environment = env
        }
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe = Pipe()
        if stdin != nil { process.standardInput = inPipe }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExecResult, Error>) in
                state.continuation = cont
                state.group.enter() // exit
                state.group.enter() // stdout
                state.group.enter() // stderr
                process.terminationHandler = { _ in state.group.leave() }
                state.group.notify(queue: DispatchQueue.global(qos: .utility)) { state.finish() }

                do {
                    try process.run()
                } catch {
                    state.failEarly(error)
                    return
                }
                state.markStarted()
                Self.closeParentEnds(out: outPipe, err: errPipe, input: stdin != nil ? inPipe : nil)
                Self.capture(outPipe.fileHandleForReading, into: state, stdout: true)
                Self.capture(errPipe.fileHandleForReading, into: state, stdout: false)

                if let stdin {
                    DispatchQueue.global(qos: .utility).async {
                        try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
                        try? inPipe.fileHandleForWriting.close()
                    }
                }
                state.armTimeout(timeout)
            }
        } onCancel: {
            state.cancel()
        }
    }

    // MARK: - 流式下载（远端 stdout → 本地文件）

    public static func download(executable: String, arguments: [String],
                                to fileURL: URL, timeout: TimeInterval = 3600) async throws {
        _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        let state = RunState()
        let process = state.process
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                state.voidContinuation = cont
                state.group.enter()
                state.group.enter()
                state.group.enter()
                process.terminationHandler = { _ in state.group.leave() }
                state.group.notify(queue: DispatchQueue.global(qos: .utility)) {
                    try? handle.close()
                    state.finishVoid()
                }

                do { try process.run() } catch {
                    try? handle.close()
                    state.failEarlyVoid(error)
                    return
                }
                state.markStarted()
                Self.closeParentEnds(out: outPipe, err: errPipe, input: nil)

                // 流式写入目标文件，内存占用恒定 64KB
                let fd = outPipe.fileHandleForReading.fileDescriptor
                DispatchQueue.global(qos: .utility).async {
                    var buf = [UInt8](repeating: 0, count: 65536)
                    while true {
                        let n = read(fd, &buf, buf.count)
                        if n <= 0 { break }
                        do { try handle.write(contentsOf: Data(buf[0..<n])) }
                        catch { state.recordIOError(error); break }
                    }
                    state.group.leave()
                }
                Self.capture(errPipe.fileHandleForReading, into: state, stdout: false)
                state.armTimeout(timeout)
            }
        } onCancel: {
            state.cancel()
        }
    }

    // MARK: - 流式上传（本地文件 → 远端 stdin）

    public static func upload(executable: String, arguments: [String],
                              from fileURL: URL, timeout: TimeInterval = 3600) async throws {
        let source = try FileHandle(forReadingFrom: fileURL)
        let state = RunState()
        let process = state.process
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                state.voidContinuation = cont
                state.group.enter()
                state.group.enter()
                state.group.enter()
                process.terminationHandler = { _ in state.group.leave() }
                state.group.notify(queue: DispatchQueue.global(qos: .utility)) {
                    try? source.close()
                    state.finishVoid()
                }

                do { try process.run() } catch {
                    try? source.close()
                    state.failEarlyVoid(error)
                    return
                }
                state.markStarted()
                Self.closeParentEnds(out: outPipe, err: errPipe, input: inPipe)
                Self.capture(outPipe.fileHandleForReading, into: state, stdout: true)
                Self.capture(errPipe.fileHandleForReading, into: state, stdout: false)

                DispatchQueue.global(qos: .utility).async {
                    let writer = inPipe.fileHandleForWriting
                    defer { try? writer.close() }
                    while true {
                        if state.isFinishedOrCancelled { return }
                        do {
                            guard let chunk = try source.read(upToCount: 256 * 1024), !chunk.isEmpty else { return }
                            try writer.write(contentsOf: chunk)
                        } catch {
                            state.recordIOError(error)
                            state.terminate()
                            return
                        }
                    }
                }
                state.armTimeout(timeout)
            }
        } onCancel: {
            state.cancel()
        }
    }

    // MARK: - 管道工具

    private static func closeParentEnds(out: Pipe, err: Pipe, input: Pipe?) {
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()
        if let input { try? input.fileHandleForReading.close() }
    }

    private static func capture(_ handle: FileHandle, into state: RunState, stdout: Bool) {
        DispatchQueue.global(qos: .utility).async {
            let data = handle.readDataToEndOfFile()
            if stdout { state.appendStdout(data) } else { state.appendStderr(data) }
            state.group.leave()
        }
    }

    // MARK: - 内部状态机

    private final class RunState: @unchecked Sendable {
        let process = Process()
        let group = DispatchGroup()
        private let lock = NSLock()
        private var stdout = Data()
        private var stderr = Data()
        private var finished = false
        private var started = false
        private var timedOut = false
        private var cancelled = false
        private var ioError: Error?
        var continuation: CheckedContinuation<ExecResult, Error>?
        var voidContinuation: CheckedContinuation<Void, Error>?

        var isFinishedOrCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return finished || cancelled
        }

        func appendStdout(_ data: Data) { lock.lock(); stdout.append(data); lock.unlock() }
        func appendStderr(_ data: Data) { lock.lock(); stderr.append(data); lock.unlock() }
        func recordIOError(_ error: Error) { lock.lock(); if ioError == nil { ioError = error }; lock.unlock() }

        func markStarted() {
            lock.lock(); started = true; lock.unlock()
        }

        /// 直接用 POSIX 信号终止：corelibs-foundation 的 Process.terminate()
        /// 在 Linux 上不可靠，kill(2) 在 macOS/Linux 行为一致。
        func terminate() {
            lock.lock()
            let pid = process.processIdentifier
            let active = started && !finished
            lock.unlock()
            if active && pid > 0 { kill(pid, SIGTERM) }
        }

        func armTimeout(_ seconds: TimeInterval) {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let done = self.finished
                let active = self.started
                let pid = self.process.processIdentifier
                if !done { self.timedOut = true }
                self.lock.unlock()
                if !done && active && pid > 0 {
                    kill(pid, SIGTERM)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                        guard let self else { return }
                        self.lock.lock()
                        let stillActive = !self.finished
                        self.lock.unlock()
                        if stillActive { kill(pid, SIGKILL) }
                    }
                }
            }
        }

        func cancel() {
            lock.lock()
            if !finished { cancelled = true }
            lock.unlock()
            terminate()
        }

        private func snapshot() -> (Data, Data, Int32, Bool, Bool, Error?) {
            lock.lock(); defer { lock.unlock() }
            return (stdout, stderr, process.terminationStatus, timedOut, cancelled, ioError)
        }

        func finish() {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            let cont = continuation
            continuation = nil
            lock.unlock()
            let (out, err, code, to, ca, io) = snapshot()
            if to { cont?.resume(throwing: SSHError.timeout) }
            else if ca { cont?.resume(throwing: SSHError.cancelled) }
            else if let io { cont?.resume(throwing: io) }
            else { cont?.resume(returning: ExecResult(stdout: out, stderr: err, exitCode: code)) }
        }

        func finishVoid() {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            let cont = voidContinuation
            voidContinuation = nil
            lock.unlock()
            let (_, err, code, to, ca, io) = snapshot()
            if to { cont?.resume(throwing: SSHError.timeout) }
            else if ca { cont?.resume(throwing: SSHError.cancelled) }
            else if let io { cont?.resume(throwing: io) }
            else if code != 0 {
                let msg = String(data: err.prefix(600), encoding: .utf8) ?? "未知错误"
                cont?.resume(throwing: SSHError.execFailed(code: code, message: msg.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else { cont?.resume(returning: ()) }
        }

        func failEarly(_ error: Error) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(throwing: SSHError.launchFailed(error.localizedDescription))
        }

        func failEarlyVoid(_ error: Error) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            let cont = voidContinuation
            voidContinuation = nil
            lock.unlock()
            cont?.resume(throwing: SSHError.launchFailed(error.localizedDescription))
        }
    }
}