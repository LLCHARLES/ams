import Foundation
import os

struct ActivityContent<T: Sendable>: Sendable { let state: T }

final class BackgroundTask {
    let valid = true
    func end() {}
}

enum HarnessTransport {
    static let dismissed = AsyncStream<[String]>.makeStream()
    static let cancelled = AsyncStream<String>.makeStream()
    static let started = AsyncStream<String>.makeStream()
    static let cancellations = OSAllocatedUnfairLock(initialState: [String]())
    static let gates = OSAllocatedUnfairLock(initialState: [String: CheckedContinuation<Void, Never>]())
    static func update(_ id: String) async {
        await withTaskCancellationHandler {
            // Unlike Task.sleep, a system call need not return when cancelled.
            await withCheckedContinuation { continuation in
                gates.withLock { $0[id] = continuation }
                started.continuation.yield(id)
            }
        } onCancel: {
            cancellations.withLock { $0.append(id) }
            cancelled.continuation.yield(id)
        }
    }
    static func release(_ id: String) { gates.withLock { $0.removeValue(forKey: id) }?.resume() }
}

enum HarnessClock {
    struct Waiting {
        var continuation: CheckedContinuation<Void, Error>?
        var cancelled = false
    }
    static let waiting = OSAllocatedUnfairLock(initialState: Waiting())
    static let started = AsyncStream<Void>.makeStream()
    static func sleep() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiting.withLock { state in
                    if state.cancelled { continuation.resume(throwing: CancellationError()) }
                    else { state.continuation = continuation }
                }
                started.continuation.yield(())
            }
        } onCancel: {
            waiting.withLock { state in
                state.cancelled = true
                state.continuation?.resume(throwing: CancellationError())
                state.continuation = nil
            }
        }
    }
}

// The build inserts the production queue and deferred resend here, replacing only the sleep boundary.
// PRODUCTION

extension SGLiveActivityBridge {
    static func check() async {
        let dismiss = CommandLine.arguments.contains("--dismiss")
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            fputs("FAIL ActivityKit send/cancellation did not complete\n", stderr)
            exit(1)
        }
        let old = Task { await quietForASecond(since: 0) }
        var started = HarnessClock.started.stream.makeAsyncIterator()
        await started.next()
        func update(_ id: String) { queue(.update(id, ActivityContent(state: 1), background: false)) }
        update("old")
        guard await old.value == false else {
            fputs("FAIL obsolete activity was admitted for resend\n", stderr)
            exit(1)
        }
        var sending = HarnessTransport.started.stream.makeAsyncIterator()
        let first = await sending.next()
        var cancelled = HarnessTransport.cancelled.stream.makeAsyncIterator()
        if dismiss {
            // Disable stops the producer; this is the final enqueue. The first
            // update ignores cancellation and stays in transport until released.
            queue(.end(["card"], background: false))
            var ended = HarnessTransport.dismissed.stream.makeAsyncIterator()
            guard await ended.next() == ["card"], await cancelled.next() == "old" else { exit(1) }
            HarnessTransport.release("old")
            timeout.cancel()
            print("PASS dismissal delivered past a stalled update without another enqueue")
            return
        }
        update("replacement")
        let second = await sending.next()
        guard first == "old", second == "replacement", await cancelled.next() == "old" else { exit(1) }
        update("next")
        // If another sender is allowed through, the second call gets cancelled
        // instead of draining the pending change when released.
        guard HarnessTransport.cancellations.withLock({ $0 }) == ["old"] else {
            fputs("FAIL stalled send must be cancelled without cancelling its replacement\n", stderr)
            exit(1)
        }
        HarnessTransport.release("replacement")
        guard await sending.next() == "next" else { exit(1) }
        HarnessTransport.release("old")
        HarnessTransport.release("next")
        timeout.cancel()
        print("PASS stuck sender cancelled, only one successor admitted")
        print("PASS newer ActivityKit change cancels deferred resend without advancing its clock")
    }
}

@main struct Check {
    static func main() async { await SGLiveActivityBridge.check() }
}
