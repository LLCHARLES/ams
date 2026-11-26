#!/usr/bin/env python3
"""Regression: python3 harness/test-sim-launch.py <booted-udid>."""
import os
from pathlib import Path
import platform
import plistlib
import signal
import socket
import subprocess
import sys
import tempfile


def check(device, work):
    bundle = f"com.retrine.launch-test-{os.getpid()}"
    app = work / "Probe.app"
    app.mkdir()
    (app / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "Probe", "CFBundleIdentifier": bundle,
        "CFBundleName": "Probe", "CFBundleVersion": "1", "CFBundlePackageType": "APPL",
    }))
    subprocess.run(["xcrun", "--sdk", "iphonesimulator", "clang", "-target",
                    f"{platform.machine()}-apple-ios17.0-simulator", "-x", "c", "-", "-o", app / "Probe"],
                   check=True, text=True, input=r"""
#include <arpa/inet.h>
#include <stdlib.h>
#include <unistd.h>
int main(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in local = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
                                .sin_port = htons(atoi(getenv("PROBE_PORT")))};
    char go;
    if (connect(fd, (struct sockaddr *)&local, sizeof(local)) || read(fd, &go, 1) != 1) return 1;
    write(STDOUT_FILENO, "final stdout\n", 13);
    write(STDERR_FILENO, "final stderr\n", 13);
    _exit(23);
}
""")
    subprocess.run(["xcrun", "simctl", "install", device, app], check=True)
    try:
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0))
            server.listen()
            server.settimeout(120)
            proc = subprocess.Popen([sys.executable, Path(__file__).with_name("sim-launch.py"), device, bundle],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    env=dict(os.environ, SIMCTL_CHILD_PROBE_PORT=str(server.getsockname()[1])))
            try:
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(30)
                    proc.send_signal(signal.SIGSTOP)
                    _, state = os.waitpid(proc.pid, os.WUNTRACED)
                    if not os.WIFSTOPPED(state):
                        raise RuntimeError("launcher did not stop")
                    conn.sendall(b"+")
                    if conn.recv(1) != b"":  # EOF: probe exited without the driver being scheduled.
                        raise RuntimeError("expected probe exit")
                proc.send_signal(signal.SIGCONT)
                out, err = proc.communicate(timeout=30)
                if proc.returncode != 23 or b"final stdout\n" not in out or b"final stderr\n" not in err:
                    raise RuntimeError(f"status {proc.returncode}, stdout {out!r}, stderr {err!r}")
            finally:
                if proc.poll() is None:
                    proc.send_signal(signal.SIGCONT)
                    proc.terminate()
                    proc.wait(timeout=40)
    finally:
        subprocess.run(["xcrun", "simctl", "uninstall", device, bundle], check=True)
    print("PASS: final stdout, stderr and app status 23 survived a stopped launcher")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        check(sys.argv[1], Path(tmp))
