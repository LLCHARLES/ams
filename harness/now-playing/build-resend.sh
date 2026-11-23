#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC=${SRC:-"$HERE/../../tweak/Sources"}
OUT=${OUT:-"$HERE/build-resend"}
mkdir -p "$OUT"
# Like the Logos harness, compile the owner unchanged except for unavailable platform boundaries.
# ActivityKit delivery is stubbed; this check owns cancellation of the pre-delivery delay only.
python3 - "$SRC/Shared/LiveActivity/LiveActivityBridge.swift" "$HERE/resend-check.swift" "$OUT/check.swift" <<'PY'
import pathlib, sys
source, fixture, output = map(pathlib.Path, sys.argv[1:])
text = source.read_text()
queue = text[text.index("    private enum Change:"):text.index("    // In the background, iOS lets")]
delay = text[text.index("    private static func quietForASecond"):text.index("    // The last state sent")]
delay = delay.replace("Task.sleep(nanoseconds: 1_000_000_000)", "HarnessClock.sleep()")
owner = 'final class SGLiveActivityBridge {\nprivate typealias State = Int\nprivate static let log = Logger()\nprivate static func send() async {}\n' + queue + delay + '\n}'
output.write_text(fixture.read_text().replace("// PRODUCTION", owner))
PY
xcrun swiftc -parse-as-library "$OUT/check.swift" -o "$OUT/resend"
"$OUT/resend"
