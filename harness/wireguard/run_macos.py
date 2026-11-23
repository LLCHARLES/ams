#!/usr/bin/env python3
"""Exercise Apple's session hooks and the engine with an explicit real profile.

The profile and fault variants live only in a temporary directory. No key,
profile contents or unmasked exit address is printed. Native image admission
uses test doubles here; real Spotify import slots require device acceptance.
"""
import argparse
import base64
import http.server
import select
import socketserver
import ssl
import json
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
WG = ROOT / "WireGuard"


def sh(cmd, **kw):
    print("+", " ".join(str(c) for c in cmd), flush=True)
    return subprocess.run(cmd, check=True, **kw)


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.0.2.1", 9))  # no packet is sent for UDP connect
        ip = s.getsockname()[0]
        return None if ip.startswith("127.") else ip
    except OSError:
        return None
    finally:
        s.close()


class DirectHandler(http.server.BaseHTTPRequestHandler):
    hits = 0

    def do_GET(self):
        DirectHandler.hits += 1
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"direct")

    def log_message(self, *args):
        pass


def exact(sock, n):
    data = b""
    while len(data) < n:
        part = sock.recv(n - len(data))
        if not part:
            raise EOFError
        data += part
    return data


class Origin(http.server.BaseHTTPRequestHandler):
    hits = 0
    body = b"external-proxy-range-fixture"

    def do_GET(self):
        Origin.hits += 1
        if self.headers.get("Range") == "bytes=0-9":
            self.send_response(206)
            self.send_header("Content-Range", f"bytes 0-9/{len(self.body)}")
            self.send_header("Content-Length", "10")
            self.end_headers()
            self.wfile.write(self.body[:10])
        else:
            self.send_response(200)
            self.send_header("Content-Length", str(len(self.body)))
            self.end_headers()
            self.wfile.write(self.body)

    def log_message(self, *args):
        pass


class FixtureProxy(socketserver.ThreadingTCPServer):
    """HTTP CONNECT or SOCKS5 proxy that maps fixture.invalid to 127.0.0.1."""
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, kind, user, password, tls=None):
        super().__init__(("127.0.0.1", 0), ProxyHandler)
        self.kind, self.user, self.password, self.hits = kind, user, password, 0
        if tls:
            self.socket = tls.wrap_socket(self.socket, server_side=True)


class ProxyHandler(socketserver.BaseRequestHandler):
    def handle(self):
        s, srv = self.request, self.server
        s.settimeout(8)
        try:
            if srv.kind == "socks5":
                _, count = exact(s, 2)
                methods = exact(s, count)
                need = 2 if srv.user else 0
                if need not in methods:
                    s.sendall(b"\x05\xff")
                    return
                s.sendall(bytes([5, need]))
                if need:
                    exact(s, 1)
                    user = exact(s, exact(s, 1)[0])
                    password = exact(s, exact(s, 1)[0])
                    ok = user == srv.user.encode() and password == srv.password.encode()
                    s.sendall(bytes([1, 0 if ok else 1]))
                    if not ok:
                        return
                _, cmd, _, atyp = exact(s, 4)
                assert cmd == 1
                if atyp == 3:
                    host = exact(s, exact(s, 1)[0]).decode()
                elif atyp == 1:
                    host = socket.inet_ntoa(exact(s, 4))
                else:
                    host = socket.inet_ntop(socket.AF_INET6, exact(s, 16))
                port = int.from_bytes(exact(s, 2), "big")
                if host != "fixture.invalid":
                    s.sendall(b"\x05\x04\x00\x01" + b"\x00" * 6)
                    return
                upstream = socket.create_connection(("127.0.0.1", port), 5)
                s.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")
            else:
                header = b""
                while not header.endswith(b"\r\n\r\n"):
                    header += exact(s, 1)
                method, target, _ = header.split(b"\r\n")[0].decode().split(" ", 2)
                assert method == "CONNECT"
                if srv.user:
                    token = base64.b64encode(f"{srv.user}:{srv.password}".encode()).decode()
                    if f"proxy-authorization: basic {token}".lower() not in header.decode().lower():
                        s.sendall(b'HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="fixture"\r\n'
                                  b"Content-Length: 0\r\nConnection: close\r\n\r\n")
                        return
                host, port = target.rsplit(":", 1)
                if host != "fixture.invalid":
                    s.sendall(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
                    return
                upstream = socket.create_connection(("127.0.0.1", int(port)), 5)
                s.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            srv.hits += 1
            with upstream:
                while True:
                    ready, _, _ = select.select([s, upstream], [], [], 8)
                    if not ready:
                        return
                    for src in ready:
                        data = src.recv(65536)
                        if not data:
                            return
                        (upstream if src is s else s).sendall(data)
        except (OSError, EOFError, AssertionError, ValueError, ssl.SSLError):
            pass


def serve(server):
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def external_proxy_tests(harness, tmp, results):
    cert, key, der = tmp / "origin.pem", tmp / "origin.key", tmp / "origin.der"
    sh(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-keyout", str(key), "-out", str(cert),
        "-subj", "/CN=fixture.invalid", "-addext", "subjectAltName=DNS:fixture.invalid",
        "-addext", "extendedKeyUsage=serverAuth", "-addext", "keyUsage=digitalSignature,keyEncipherment", "-sha256"],
       capture_output=True)
    sh(["openssl", "x509", "-in", str(cert), "-outform", "DER", "-out", str(der)])
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(cert, key)
    origin = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Origin)
    origin.socket = tls.wrap_socket(origin.socket, server_side=True)
    serve(origin)
    url = f"https://fixture.invalid:{origin.server_port}/media"
    closed = socket.socket()
    closed.bind(("127.0.0.1", 0))
    closed_port = closed.getsockname()[1]
    closed.close()
    cases = [
        ("http", "u-fixture", "p-fixture", "p-fixture", None, True, "HTTP CONNECT with Basic auth (407 challenge)"),
        ("http", "", "", "", None, True, "HTTP CONNECT without auth"),
        ("socks5", "u-fixture", "p-fixture", "p-fixture", None, True, "SOCKS5 with user/password"),
        ("socks5", "u-fixture", "p-fixture", "wrong", None, False, "SOCKS5 wrong password"),
        ("https", "", "", "", tls, False, "HTTPS proxy with untrusted certificate"),
        ("http", "", "", "", "closed", False, "unreachable HTTP proxy"),
    ]
    for kind, user, server_pass, client_pass, extra, ok, name in cases:
        proxy = None
        if extra == "closed":
            port = closed_port
        else:
            proxy = serve(FixtureProxy("socks5" if kind == "socks5" else "http", user, server_pass,
                                       tls=extra if kind == "https" else None))
            port = proxy.server_address[1]
        before = Origin.hits
        env = dict(os.environ, SGWG_TEST_ENABLED="1", SGWG_TEST_APP_VERSION="9.1.90",
                   SGWG_TEST_KIND=kind, SGWG_TEST_HOST="127.0.0.1",
                   SGWG_TEST_PORT=str(port), SGWG_TEST_USER=user, SGWG_TEST_PASS=client_pass,
                   SGWG_TEST_ORIGIN_URL=url, SGWG_TEST_CERT=str(der), SGWG_TEST_TRUST_SUFFIX="fixture.invalid",
                   SGWG_EXPECT_OK="1" if ok else "0")
        proc = subprocess.run([str(harness), "external"], env=env, capture_output=True, text=True, timeout=120)
        sys.stdout.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        if proc.returncode != 0:
            raise SystemExit(f"FAILED: external {name} (exit {proc.returncode})")
        if ok:
            assert Origin.hits > before and proxy.hits > 0, (name, Origin.hits, before)
        else:
            assert Origin.hits == before, f"{name}: origin was reached"
        if proxy:
            proxy.shutdown()
            proxy.server_close()
        results.append(f"external {kind}: {name} -> {'206 via proxy' if ok else 'blocked, origin not reached'}")
    origin.shutdown()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=pathlib.Path)
    parser.add_argument("--live-profile", type=pathlib.Path, required=True)
    parser.add_argument("--expect-country", required=True)
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix="sgwg-") as tmp:
        tmp = pathlib.Path(tmp)
        profile = tmp / "client.conf"
        shutil.copyfile(args.live_profile, profile)
        profile.chmod(0o600)
        env = dict(os.environ, CGO_ENABLED="1")
        sh(["go", "build", "-buildmode=c-archive", "-o", str(tmp / "libsgwg-macos.a"), "."], cwd=WG, env=env)
        harness = tmp / "harness"
        sh(["xcrun", "clang", "-fobjc-arc", "-fmodules", "-DSGWG_TESTING", "-mmacosx-version-min=14.0", "-Wall",
            "-I", str(ROOT / "tweak/Sources"),
            str(ROOT / "tweak/Sources/Shared/WireGuard/SGWGCore.m"), str(ROOT / "tweak/Sources/Shared/WireGuard/SGWGTransport.m"),
            str(ROOT / "tweak/Sources/Shared/LyricsSources/LyricsHosts.m"),
            str(ROOT / "tweak/Sources/Shared/WireGuard/SGWGNative.m"),
            str(ROOT / "tweak/Sources/Shared/WireGuard/SGWGAdmission.m"),
            str(ROOT / "harness/wireguard/harness.m"), str(tmp / "libsgwg-macos.a"),
            "-framework", "Foundation", "-framework", "Network", "-framework", "Security",
            "-framework", "CoreFoundation", "-lresolv", "-o", str(harness)])

        with urllib.request.urlopen("https://www.cloudflare.com/cdn-cgi/trace", timeout=20) as response:
            direct_trace = dict(line.split("=", 1) for line in response.read(8192).decode().splitlines() if "=" in line)
        if not direct_trace.get("ip"):
            raise SystemExit("Direct exit baseline did not return an IP")
        print("Direct Mac exit country:", direct_trace.get("loc", "unknown"))
        direct = http.server.ThreadingHTTPServer(("0.0.0.0", 0), DirectHandler)
        thread = threading.Thread(target=direct.serve_forever, daemon=True)
        thread.start()
        try:
            ip = lan_ip()
            if not ip:
                raise SystemExit("No LAN address for the direct-fallback probe")
            direct_url = f"http://{ip}:{direct.server_port}/direct"
            with urllib.request.urlopen(direct_url, timeout=5) as response:
                if response.status != 200:
                    raise SystemExit("Direct sentinel baseline failed")
            DirectHandler.hits = 0
            base = dict(os.environ, SGWG_TEST_ENABLED="1", SGWG_TEST_PROFILE=str(profile),
                        SGWG_TEST_DIRECT_URL=direct_url, SGWG_DIRECT_IP=direct_trace["ip"],
                        SGWG_EXPECT_COUNTRY=args.expect_country,
                        SGWG_TEST_APP_VERSION="9.1.90", SGWG_TEST_APP_BUILD="919002269", SGWG_EXPECT_ACTIVE="1")

            def run(name, mode, **extra):
                proc = subprocess.run([str(harness), mode], env=dict(base, **extra), capture_output=True, text=True, timeout=300)
                sys.stdout.write(proc.stdout)
                sys.stderr.write(proc.stderr)
                if proc.returncode != 0:
                    raise SystemExit(f"FAILED: {name} (exit {proc.returncode})")
                results.append(name)
                return proc.stdout

            run("unit: Spotify delegates, ABI guards, proxy enforcement and redaction", "unit")
            run("unit: disabled -> no hooks", "unit", SGWG_TEST_ENABLED="0", SGWG_EXPECT_ACTIVE="0")
            run("failclosed: saved opt-in on an uninspected version", "failclosed",
                SGWG_TEST_APP_VERSION="9.1.95", SGWG_EXPECT_BLOCKED="1")
            run("failclosed: wrong build", "failclosed", SGWG_TEST_APP_BUILD="919002270", SGWG_EXPECT_BLOCKED="1")
            out = run("live Proton: handshake, US exit, HTTPS and range", "live")
            report = out[out.find("Retrine app-local WireGuard diagnostics"):]
            source = profile.read_text()
            for name, field, replacement in [
                ("bad endpoint", "Endpoint", "127.0.0.1:1"),
                ("wrong peer key", "PublicKey", base64.b64encode(bytes([1]) * 32).decode()),
            ]:
                changed, count = re.subn(rf"(?mi)^\s*{field}\s*=.*$", f"{field} = {replacement}", source)
                if count != 1:
                    raise SystemExit(f"Expected exactly one {field} for fault injection")
                fault = tmp / "fault.conf"
                fault.write_text(changed)
                fault.chmod(0o600)
                run(f"failclosed: {name}", "failclosed", SGWG_TEST_PROFILE=str(fault))
            if DirectHandler.hits != 0:
                raise SystemExit("Direct server was contacted by a covered request")
            results.append("direct sentinel: zero hits with live and faulted profiles")
            external_proxy_tests(harness, tmp, results)
        finally:
            direct.shutdown()
            direct.server_close()
            thread.join()

    summary = {
        "platform": f"macOS {subprocess.run(['sw_vers', '-productVersion'], capture_output=True, text=True).stdout.strip()} (Foundation + Network.framework, same proxy API as iOS 17+)",
        "passed": results,
        "diagnostics_sample": report,
        "not_covered": ["real Spotify image admission and import slots", "UIKit settings screen",
                        "music playback, next track, lock-screen playback", "Wi-Fi/cellular switching"],
    }
    print(json.dumps(summary, indent=2, ensure_ascii=False))
    if args.out:
        args.out.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
