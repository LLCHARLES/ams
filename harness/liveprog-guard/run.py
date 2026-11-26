#!/usr/bin/env python3
"""Build/run the real engine; negative mutations require explicit manual opt-in."""
import argparse
import pathlib
import platform
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
FX = ROOT / "tweak/Sources/Shared/AudioEffects"
VENDOR = ROOT / "vendor/audio"
HERE = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mutations", action="store_true", help="run manual mutation proofs")
args = parser.parse_args()


def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


with tempfile.TemporaryDirectory(prefix="retrine-liveprog-guard-") as directory:
    out = pathlib.Path(directory)
    run(["make", "-s", "-C", VENDOR, "PLATFORM=mac", f"BUILD={out / 'vendor'}", "-j8"])
    flags = ["xcrun", "clang", "-fobjc-arc", "-O2", "-g", "-Wall", "-Werror",
             "-target", f"{platform.machine()}-apple-macos13.0", "-I", ROOT / "tweak/Sources", "-I", FX]
    for include in ("libbs2b", "eel2-parser", "wdl/eel2"):
        flags += ["-isystem", VENDOR / include]
    objects = []
    for name in ("SGDSPFilters", "SGDSPConvolver", "SGDSPTone", "SGDSPDynamics",
                 "SGDSPCrossfeed", "SGDSPReverb", "SGDSPLiveprog"):
        obj = out / f"{name}.o"
        run(flags + ["-c", FX / f"{name}.m", "-o", obj])
        objects.append(obj)
    source = (FX / "SGDSPEngine.m").read_text()
    host = (FX / "AudioEffects.x").read_text()
    errors = host.split("#pragma mark - errors\n", 1)[1].split(
        "#pragma mark - the queue: setting the effects\n", 1)[0]
    (out / "AudioEffectsErrors.m").write_text(errors)
    constants = host[host.index("static const double kApplyAfter"):host.index("enum { kScratchFrames")]
    config = host.split("#pragma mark - the queue: setting the effects\n", 1)[1].split(
        "// The engine is read out once a second", 1)[0]
    pending = host[host.index("static os_unfair_lock sg_pendingLock"):host.index("#pragma mark - what the page shows")]
    (out / "AudioEffectsConfig.m").write_text(constants + config)
    (out / "AudioEffectsApply.m").write_text(pending)
    route = host[host.index("static void followRoute(void)"):host.index("%ctor {")]
    (out / "AudioEffectsRoute.m").write_text(route)
    flags += ["-I", out]
    localize = out / "SGLocalize.o"
    run(flags + ["-c", ROOT / "tweak/Sources/Core/SGLocalize.m", "-o", localize])
    objects.append(localize)

    def build(name, text):
        engine = out / f"{name}.m"
        engine.write_text(text)
        obj = out / f"{name}.o"
        run(flags + ["-Dmach_absolute_time=guard_clock", "-DSGDSPLiveprogRun=guard_run",
                     "-DSGDSPLiveprogCreate=guard_create", "-DSGDSPLiveprogFree=guard_free",
                     "-Ddispatch_semaphore_signal=guard_signal",
                     "-c", engine, "-o", obj])
        executable = out / name
        run(flags + [HERE / "main.m", obj] + objects +
            [out / "vendor/libsgaudio.a", "-framework", "Foundation",
             "-framework", "AudioToolbox", "-framework", "Accelerate", "-o", executable])
        return executable

    executable = build("guard", source)
    for case in ("thresholds", "normal", "heavy", "limits", "deadline", "abandonment", "messages", "quarantine", "adjacent"):
        run([executable, case], timeout=15)

    if not args.mutations:
        raise SystemExit(0)

    mutations = [
        ("consecutive", "engine->liveprogOverBudget >= kLiveprogConsecutiveBlocks",
         "engine->liveprogOverBudget > kLiveprogConsecutiveBlocks", "thresholds"),
        ("single", "nanos > durationNanos ||", "false ||", "thresholds"),
        ("bypass",
         "if (s == SlotLiveprog) {\n            if (engine->liveprogTailPending)",
         "if (false) {\n            if (engine->liveprogTailPending)", "thresholds"),
        ("normal", "nanos > durationNanos ||", "nanos > 0 ||", "normal"),
        ("reset", "atomic_exchange_explicit(&engine->liveprogTripped, false, memory_order_acq_rel)",
         "atomic_load_explicit(&engine->liveprogTripped, memory_order_acquire)", "thresholds"),
        ("deadline", "kLiveprogStartSeconds = 2", "kLiveprogStartSeconds = 4", "deadline"),
        ("preserve", "copyError(error, errorSize, kLiveprogStartError);\n            return false;",
         "install(engine, SlotLiveprog, NULL);\n"
         "            copyError(error, errorSize, kLiveprogStartError);\n            return false;", "deadline"),
        ("cleanup", "SGDSPLiveprogFree(job->result);", "(void)job->result;", "abandonment"),
        ("slow", "if (job->expired || job->slow) {", "if (job->expired) {", "limits"),
        ("quarantine",
         "if (slot == SlotLiveprog) {\n        // Recheck",
         "if (slot == SlotLiveprog) {\n"
         "        atomic_store(&sg_liveprogQuarantined, false);\n"
         "        atomic_store(&engine->liveprogTripped, false);\n        // Recheck", "quarantine"),
        ("adjacent",
         "if (slot == SlotLiveprog) {\n        // Recheck",
         "if (slot == SlotLiveprog) {\n        engine->liveprogTailPending = false;\n        // Recheck",
         "adjacent"),
    ]
    for name, old, new, case in mutations:
        if source.count(old) != 1:
            raise RuntimeError(f"mutation {name}: expected one live source match")
        mutant = build(name, source.replace(old, new))
        result = subprocess.run([str(mutant), case], text=True, capture_output=True, timeout=15)
        if result.returncode != 1 or "FAIL:" not in result.stderr:
            raise RuntimeError(f"mutation {name} was not caught: {result.returncode}\n"
                               f"{result.stdout}\n{result.stderr}")
        print(f"PASS mutation {name}: {result.stderr.strip()}", flush=True)

    old = " && !sg_followingRoute"
    if pending.count(old) != 1:
        raise RuntimeError("route mutation: expected one live source match")
    (out / "AudioEffectsApply.m").write_text(pending.replace(old, ""))
    mutant = build("route", source)
    result = subprocess.run([str(mutant), "quarantine"], text=True, capture_output=True, timeout=15)
    if result.returncode != 1 or "FAIL:" not in result.stderr:
        raise RuntimeError(f"route mutation was not caught: {result.stdout}\n{result.stderr}")
    print(f"PASS mutation route: {result.stderr.strip()}", flush=True)
    (out / "AudioEffectsApply.m").write_text(pending)

    old = "if (SGDSPEngineLiveprogError(engine))"
    if errors.count(old) != 1:
        raise RuntimeError("message mutation: expected one live source match")
    (out / "AudioEffectsErrors.m").write_text(errors.replace(old, "if (engine && false)"))
    mutant = build("messages", source)
    result = subprocess.run([str(mutant), "messages"], text=True, capture_output=True, timeout=15)
    if result.returncode != 1 or "SGDSPError exposes the runaway message" not in result.stderr:
        raise RuntimeError(f"message mutation was not caught: {result.stdout}\n{result.stderr}")
    print(f"PASS mutation messages: {result.stderr.strip()}", flush=True)
