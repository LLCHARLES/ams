#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC=${SRC:-"$HERE/../../tweak/Sources"}
OUT=${OUT:-"$HERE/build-resend"}
mkdir -p "$OUT"
# Like the Logos harness, compile the owner unchanged except for unavailable platform boundaries.
# Replace the ActivityKit transport and UIKit assertion, not the queue or its send loop.
python3 - "$SRC/Shared/LiveActivity/LiveActivityBridge.swift" "$HERE/resend-check.swift" "$OUT/check.swift" <<'PY'
import pathlib, sys
source, fixture, output = map(pathlib.Path, sys.argv[1:])
text = source.read_text()
queue = text[text.index("    private enum Change:"):text.index("    // In the background, iOS lets")]
delay = text[text.index("    private static func quietForASecond"):text.index("    // The last state sent")]
delay = delay.replace("Task.sleep(nanoseconds: 1_000_000_000)", "HarnessClock.sleep()")
sender = text[text.index("    private actor BackgroundTime"):text.index("    // A new activity can only be requested")]
owner = '''final class SGLiveActivityBridge {
private typealias State = Int
private static let log = Logger()
private static let ending = OSAllocatedUnfairLock(initialState: Set<String>())
private static func onlyLinesChanged(_ state: Int) -> Bool { false }
private static func update(_ id: String, _ content: ActivityContent<Int>) async { await HarnessTransport.update(id) }
private static func end(_ ids: [String]) async { HarnessTransport.dismissed.continuation.yield(ids) }
''' + queue + delay + sender + '\n}'
output.write_text(fixture.read_text().replace("// PRODUCTION", owner))
budget = text[text.index("        do {", text.index("// Budget the actual encoded state")):text.index("        let content = ActivityContent(state: state")]
test = fixture.with_name("state-budget.swift").read_text()
output.with_name("budget.swift").write_text(test.replace("// PRODUCTION BUDGET", budget.replace("JSONEncoder()", "CountingEncoder()")))
PY
xcrun swiftc -parse-as-library "$OUT/check.swift" -o "$OUT/resend"
"$OUT/resend" --dismiss
"$OUT/resend"
xcrun swift "$OUT/budget.swift"
