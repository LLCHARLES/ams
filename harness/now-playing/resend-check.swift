import Foundation
import os

struct ActivityContent<T: Sendable>: Sendable { let state: T }

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
        let timeout = Task {
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            fputs("FAIL newer change did not cancel the deferred resend\n", stderr)
            exit(1)
        }
        let old = Task { await quietForASecond(since: 0) }
        var started = HarnessClock.started.stream.makeAsyncIterator()
        await started.next()
        queue(.end(["old"], background: true))
        guard await old.value == false else {
            fputs("FAIL obsolete activity was admitted for resend\n", stderr)
            exit(1)
        }
        timeout.cancel()
        print("PASS newer ActivityKit change cancels deferred resend without advancing its clock")
    }
}

@main struct Check {
    static func main() async { await SGLiveActivityBridge.check() }
}
