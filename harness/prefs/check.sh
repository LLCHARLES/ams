#!/bin/sh
set -eu
cd "$(dirname "$0")"
OUT=${OUT:-build}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -I ../../tweak/Sources -I ../../tweak/Sources/Core \
    -framework Foundation check.m ../../tweak/Sources/Core/SGPrefs.m -o "$OUT/check"
"$OUT/check"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -I ../../tweak/Sources \
    -framework Foundation optional-work.m ../../tweak/Sources/Core/SGOptionalWork.m ../../tweak/Sources/Core/SGPrefs.m \
    ../../tweak/Sources/Core/SGLog.m -o "$OUT/optional-work"
"$OUT/optional-work"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -I ../../tweak/Sources \
    -framework Foundation counters.m ../../tweak/Sources/Core/SGFileHash.m -o "$OUT/counters"
"$OUT/counters"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -DSG_DRIVER=1 -I ../../tweak/Sources \
    -framework Foundation logging.m ../../tweak/Sources/Core/SGLog.m -o "$OUT/logging"
"$OUT/logging"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-unused-parameter -I ../../tweak/Sources \
    -framework Foundation rebind.m ../../tweak/Sources/Core/SGLog.m -o "$OUT/rebind"
for kind in none bundle bundle-alias container jailbreak roothide; do
    "$OUT/rebind" "$kind" -1
done
for refused in 0 1 2; do
    "$OUT/rebind" jailbreak "$refused"
done
