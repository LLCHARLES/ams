#!/bin/bash
# Real Foundation directories, coordinator and presenters in disposable homes. No Spotify or simulator.
set -eu
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
src=../../tweak/Sources
fx=$src/Shared/AudioEffects
# Insert a competing mkdir at the exclusive rename syscall in the EEXIST case only.
xcrun clang -fobjc-arc -Wall -Werror -Drenamex_np=SGFixtureRename -c "$src/Core/SGDataRoot.m" -o "$out/root.o"
xcrun clang -fobjc-arc -Wall -Werror -I ../autoeq/shim -I "$src" check.m "$out/root.o" \
    "$src"/Core/{SGFileHash,SGLocalize,SGPrefs}.m "$src"/Core/TranslationStore/SGTranslationFiles.m \
    "$src/Shared/LocalFiles/LyricRetirement.m" "$src/Shared/ListeningStats/SGPlayLog.m" \
    "$fx"/{AudioEffectsPresets,AudioEffectsFiles,AudioEffectsSettings,AutoEq}.m -framework Foundation -o "$out/data-migration-check"
export __CFPREFERENCES_AVOID_DAEMON=1
for scenario in fresh rename both recreated pinned denied invalid presenter race translations; do
    export CFFIXED_USER_HOME="$out/$scenario"
    mkdir "$CFFIXED_USER_HOME"
    "$out/data-migration-check" "$scenario" first
    case "$scenario" in
        rename|both|recreated|pinned|presenter|translations)
            "$out/data-migration-check" "$scenario" relaunch
            "$out/data-migration-check" "$scenario" relaunch ;;
    esac
done
