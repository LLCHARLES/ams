import Foundation
import UIKit

@main
struct OnDeviceKeptCheck {
    @MainActor static func main() {
        var presentations = 0
        var late: (() -> Void)?
        SGAfterTransition(register: { late = $0; return false }, run: { presentations += 1 })
        late?()
        guard presentations == 1 else { print("FAIL duplicate transition presentation"); exit(1) }
        let lane = SGModelLane(timeout: .milliseconds(100))
        var replies: [String] = [], started: [String] = []
        lane.submit({ _ in
            await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in
                DispatchQueue.main.async {
                    started.append("held")
                    lane.submit({ _ in started.append("obsolete"); return ([], nil) }, progress: { _ in }, done: { result in
                        if result.0 == nil { replies.append("obsolete") }
                    })
                    lane.submit({ _ in started.append("latest"); return (["done"], nil) }, progress: { _ in }, done: { result in
                        if result.0 == ["done"] { replies.append("latest") }
                    })
                }
            }
            return (["stale"], nil)
        }, progress: { _ in }, done: { result in replies.append(result.0 == nil ? "held" : "stale") })
        let limit = Date().addingTimeInterval(60)
        while !replies.contains("latest") && limit.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        guard replies == ["held", "obsolete", "latest"], started == ["held", "latest"] else {
            print("FAIL model lane: \(replies), \(started)"); exit(1)
        }
        let lines = ["The little blue robot walks through the garden with its friends.", "", "♪"]
        var finished = false
        var passed = false
        // The actual provider's same-language path must need neither downloaded languages nor a
        // TranslationSession. Its nonempty result is the existing saved-translation convention.
        SGOnDeviceTranslation.translate(lines, to: "en") { answer, error in
            passed = answer == lines && error == nil
            print("\(passed ? "PASS" : "FAIL") on-device keeps target-language text as a completed result")
            if let error { print(error) }
            finished = true
        }
        let deadline = Date().addingTimeInterval(60)
        while !finished && deadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        if !finished { print("FAIL on-device completion timed out") }
        exit(finished && passed ? 0 : 1)
    }
}
