"""Explicit immutable targets loaded from upstream-shaped JSON, never environment state.

JSON owns target facts; patchers own instruction emission. The legacy runtime
adapter is retained until the companion migration replaces its consumers.
"""
from dataclasses import dataclass
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Profile:
    version: str
    build: str
    main_uuid: bytes
    shared_uuid: bytes
    enabled: bool
    primary: bool
    setter: int
    setter_head: bytes
    vtable: int
    window: int
    provider: int
    provider_head: bytes
    mapping: int
    mapping_bytes: bytes
    dlsym: int
    dlsym_head: bytes
    success: int
    failure: int
    quota_block: int
    reservation_counters_verified: bool
    provider_context_register: int
    runtime_layout_verified: bool
    preferred: int
    request_bytes: bytes
    callback_head: bytes
    caves: tuple
    cave_capacity: int
    minimum_tracks: int
    minimum_music_duration_seconds: int
    wrapper_manager_offset: int
    queue_flags_offset: int
    provider_offset: int
    trace_owner_offset: int
    trace_descriptor_offset: int
    descriptor_file_offset: int
    dlsym_library: str
    objc_abi: tuple
    manager_field_shift: int
    render_callback: int
    jailbreak: bool
    export_points: tuple
    export_windows: tuple
    export_cave_capacity: int
    # Target provenance owns the evidence required to admit these layouts.
    @property
    def unverified_fields(self):
        return () if self.runtime_layout_verified else (
            "current_tracks", "current_episodes", "wrapper_manager",
            "queue_flags", "manager_provider", "trace_owner", "trace_descriptor",
        )

    @property
    def call_site(self):
        return self.window + 12

    @property
    def trace_points(self):
        return (
            ("Request", self.call_site, self.caves[0], bytes.fromhex("02008052"), 0),
            ("Success", self.success, self.caves[1], self.callback_head, 1),
            ("Failure", self.failure, self.caves[2], self.callback_head, 2),
        )


def load_target(path):
    data = json.loads(Path(path).read_text())
    runtime = json.loads((ROOT / "targets" / data["runtime"]).read_text())
    native, admission, export = data["native"], data["admission"], data["export"]
    address = lambda key: int(native[key], 16)
    code = lambda key: bytes.fromhex(native[key])
    traces = data["trace_points"]
    points = tuple((name, int(p["address"], 16),
                    int(p["cave"], 16) if "cave" in p else int(export["cave_base"], 16) + p["kind"] * export["cave_stride"],
                    bytes.fromhex(p["original"]), p["kind"]) for name, p in export["points"].items())
    if address("call_site") != address("window") + 12:
        raise ValueError("Unsupported key request window layout")
    return Profile(
        version=data["spotify_version"], build=data["spotify_build"],
        main_uuid=bytes.fromhex(data["uuid"]), shared_uuid=bytes.fromhex(data["shared_uuid"]),
        enabled=admission["enabled"], primary=data["primary"],
        setter=address("setter"), setter_head=code("setter_original"),
        vtable=address("manager_vtable"), window=address("window"), provider=address("provider"),
        provider_head=code("provider_head"), mapping=address("mapping"), mapping_bytes=code("mapping_original"),
        dlsym=address("dlsym_stub"), dlsym_head=code("dlsym_stub_head"),
        success=int(traces[1]["address"], 16), failure=int(traces[2]["address"], 16),
        quota_block=runtime.pop("quota_block_base") + native["manager_field_shift"],
        reservation_counters_verified=admission["reservation_counters_verified"],
        provider_context_register=native["provider_context_register"],
        runtime_layout_verified=admission["runtime_layout_verified"],
        preferred=int(data["preferred_address"], 16), request_bytes=code("window_original"),
        callback_head=bytes.fromhex(traces[1]["original"]),
        caves=tuple(int(p["cave"], 16) for p in traces) + (address("selector_cave"), address("setter_cave")),
        manager_field_shift=native["manager_field_shift"], render_callback=address("render_callback"),
        jailbreak=admission["jailbreak"], export_points=points,
        export_windows=tuple((name, int(w["address"], 16), bytes.fromhex(w["bytes"])) for name, w in export["windows"].items()),
        export_cave_capacity=export["cave_stride"],
        **{**runtime, "objc_abi": tuple(tuple(row) for row in runtime["objc_abi"])})


V9190 = load_target(ROOT / "targets/spotify-9.1.90.json")
V9200 = load_target(ROOT / "targets/spotify-9.2.0.json")
PROFILES = (V9190, V9200)

def artifact_name(mod_version, profile=None):
    suffix = "" if profile is None else "-pixie" + ("" if profile.primary else f"-spotify-{profile.version}")
    return f"retrine-{mod_version}{suffix}.ipa"


def select_profile(info, main_uuid, shared_uuid, *, require_enabled=True, jailbreak=False):
    for profile in PROFILES:
        if (info.get("CFBundleShortVersionString"), str(info.get("CFBundleVersion")),
                main_uuid, shared_uuid) == (
                profile.version, profile.build, profile.main_uuid, profile.shared_uuid):
            if jailbreak and not profile.jailbreak:
                raise ValueError("Jailbreak Pixie supports only the exact Spotify 9.1.90 profile")
            if require_enabled and not profile.enabled:
                raise ValueError(f"Pixie not yet enabled for Spotify {profile.version}; static-only, real-device capture required")
            return profile
    raise ValueError("No exact Pixie profile matches version, CFBundleVersion and both image UUIDs")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--primary-ipa", action="store_true", required=True)
    parser.parse_args()
    primary, = (profile for profile in PROFILES if profile.primary)
    print(ROOT.parent / "ipa" / f"Spotify-{primary.version}.ipa")
