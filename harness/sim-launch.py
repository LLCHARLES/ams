#!/usr/bin/env python3
"""Launch on the given simulator, inheriting SIMCTL_CHILD_* just like simctl."""
import argparse
from contextlib import closing
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

# Darwin sys/event.h; Python exposes NOTE_EXIT but not NOTE_EXITSTATUS.
NOTE_EXITSTATUS = 0x04000000


def wait_for_app(pid, stdout, stderr, deadline, live):
    streams = [(stdout, sys.stdout.buffer), (stderr, sys.stderr.buffer)]

    def drain():
        for source, dest in streams:
            shutil.copyfileobj(source, dest)
            dest.flush()

    with closing(select.kqueue()) as queue:
        # Simulator app PIDs are local Darwin PIDs on both Intel and ARM.
        # Subscribe before SIGCONT so even an immediate exit leaves a status.
        events = [select.kevent(pid, filter=select.KQ_FILTER_PROC,
                                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                                fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)]
        if live:
            # Screenshot/FIFO handshakes need lines before exit. Follow the
            # same durable files, then drain once more on the exit event.
            events.extend(select.kevent(source.fileno(), filter=select.KQ_FILTER_VNODE,
                                        flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                                        fflags=select.KQ_NOTE_WRITE) for source, _ in streams)
        queue.control(events, 0)
        os.kill(pid, signal.SIGCONT)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError
            ready = queue.control([], len(events), remaining)
            if not ready:
                raise TimeoutError
            drain()
            for event in ready:
                if event.filter == select.KQ_FILTER_PROC:
                    return os.waitstatus_to_exitcode(event.data)


def launch(args):
    # launchd_sim cannot open paths in the host's per-user /var/folders temp directory.
    device_tmp = subprocess.check_output(["xcrun", "simctl", "getenv", args.udid, "TMPDIR"],
                                         text=True, timeout=args.timeout).strip()
    with tempfile.TemporaryDirectory(prefix="sim-launch-", dir=device_tmp) as tmp:
        stdout, stderr = (Path(tmp).resolve() / name for name in ("stdout", "stderr"))
        cmd = ["xcrun", "simctl", "launch", "--wait-for-debugger", f"--stdout={stdout}", f"--stderr={stderr}"]
        if args.terminate_running_process:
            cmd.append("--terminate-running-process")
        deadline = time.monotonic() + args.timeout
        # Follow and drain the same inodes from before launch through the exit event.
        with stdout.open("x+b") as out, stderr.open("x+b") as err:
            try:
                result = subprocess.run([*cmd, args.udid, args.bundle, *args.app_args],
                                        stdout=subprocess.PIPE, text=True, timeout=args.timeout)
                if result.returncode:
                    return result.returncode
                pid = int(result.stdout.rsplit(":", 1)[1])
                status = wait_for_app(pid, out, err, deadline, args.live)
            except BaseException:
                subprocess.run(["xcrun", "simctl", "terminate", args.udid, args.bundle], timeout=30)
                raise
        if status < 0:
            print(f"{args.bundle} died by signal {-status} ({signal.strsignal(-status)})", file=sys.stderr)
            return 128 - status
        return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--terminate-running-process", action="store_true")
    parser.add_argument("--timeout", type=int, default=180, metavar="SECONDS")
    parser.add_argument("--live", action="store_true", help="also deliver file writes during interactive scenarios")
    parser.add_argument("udid")
    parser.add_argument("bundle")
    parser.add_argument("app_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")

    def terminate(signum, frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, terminate)
    try:
        return launch(args)
    except (TimeoutError, subprocess.TimeoutExpired):
        print(f"{args.bundle} timed out after {args.timeout}s; requested termination", file=sys.stderr)
        return 124


if __name__ == "__main__":
    sys.exit(main())
